"""End-to-end login flow: loopback server + simulated browser callback.

Covers the parts that previously had ZERO pytest coverage — the reason
today's SIGSEGV regression shipped.
"""

import http.client
import json
import os
import re
import shutil
import subprocess
import time
import urllib.error
import urllib.request
from pathlib import Path

import pytest

from conftest import _resolve_og


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _launch_og_login(home: Path, host: str, timeout_s: float = 8.0):
    """Spawn `og login --host <host>`, return (process, stderr_so_far).
    Waits up to timeout_s for the "Waiting for callback" banner."""
    env = os.environ.copy()
    env["HOME"] = str(home)
    env["NO_COLOR"] = "1"
    env["ORCHARDGRID_HOST"] = host
    env["OG_NO_BROWSER"] = "1"  # don't spam real browser tabs

    binary = _resolve_og()
    proc = subprocess.Popen(
        [str(binary), "login"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        env=env,
        bufsize=1,
    )

    # Drain stderr line-by-line until we see the banner or time out.
    buf: list[str] = []
    deadline = time.time() + timeout_s
    while time.time() < deadline:
        line = proc.stderr.readline()
        if not line:
            # process died
            break
        buf.append(line)
        if "Waiting for callback" in line:
            return proc, "".join(buf)
    # Ran out of patience or stream closed.
    if proc.poll() is not None:
        remaining, _ = proc.communicate(timeout=1)
        buf.append(remaining or "")
    return proc, "".join(buf)


def _extract_port_and_state(stderr: str) -> tuple[int, str]:
    m_port = re.search(r"redirect_uri=http://127\.0\.0\.1:(\d+)/cb", stderr)
    m_state = re.search(r"state=([a-f0-9]+)", stderr)
    assert m_port, f"redirect_uri port not found in: {stderr!r}"
    assert m_state, f"state not found in: {stderr!r}"
    return int(m_port.group(1)), m_state.group(1)


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------


def test_login_loopback_binds_real_port(scratch_home):
    """Loopback HTTP server must bind to a genuine ephemeral port, not 0.
    Regression guard for the NWListener `.any` → rawValue==0 bug."""
    proc, stderr = _launch_og_login(scratch_home, host="http://127.0.0.1:1")
    try:
        port, _ = _extract_port_and_state(stderr)
        assert port != 0, "loopback bound to port 0 — port-binding regression"
        assert 1024 <= port <= 65535, f"port {port} outside ephemeral range"
    finally:
        proc.terminate()
        try:
            proc.communicate(timeout=2)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.communicate()


def test_login_full_roundtrip_writes_config(mock_server, scratch_home):
    """Simulate the browser callback: spawn og login, read the loopback
    URL from its stderr, hit that URL with a synthesized token+state,
    then assert config.json was written correctly with 0600 perms."""
    proc, stderr = _launch_og_login(scratch_home, host=mock_server.url)
    try:
        port, state = _extract_port_and_state(stderr)

        # Simulate the browser after user clicked "Authorize".
        cb_url = (
            f"http://127.0.0.1:{port}/cb"
            f"?token=sk-test-management-xyz&state={state}"
        )
        with urllib.request.urlopen(cb_url, timeout=3) as resp:
            body = resp.read().decode()
        assert resp.status == 200
        assert "authorized" in body.lower() or "og" in body.lower()

        # Wait for og login to finalize (save config, print success).
        try:
            out, remaining_err = proc.communicate(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
            out, remaining_err = proc.communicate()
        stderr += remaining_err

        assert proc.returncode == 0, (
            f"og login exited non-zero: {proc.returncode} · "
            f"stdout={out!r} stderr={stderr!r}"
        )
        # "✓ logged in" is printed to stdout; the URL banner went to stderr.
        assert "logged in" in out

        # Verify config.json was written with 0600 perms and correct contents.
        cfg_path = scratch_home / ".config" / "orchardgrid" / "config.json"
        assert cfg_path.exists(), "config.json not written"
        perms = cfg_path.stat().st_mode & 0o777
        assert perms == 0o600, f"config.json perms = {oct(perms)}, expected 0600"

        cfg = json.loads(cfg_path.read_text())
        assert cfg["token"] == "sk-test-management-xyz"
        assert cfg["host"] == mock_server.url
        assert cfg.get("deviceLabel"), "deviceLabel should be non-empty"
    finally:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.communicate(timeout=2)
            except subprocess.TimeoutExpired:
                proc.kill()


def test_login_rejects_wrong_state(mock_server, scratch_home):
    """If the callback state doesn't match what the CLI generated, login
    must abort with a CSRF error and not write config."""
    proc, stderr = _launch_og_login(scratch_home, host=mock_server.url)
    try:
        port, _actual_state = _extract_port_and_state(stderr)

        # Fire callback with a state that doesn't match. Server may
        # respond normally OR cancel mid-flight when the CLI rejects;
        # both are acceptable outcomes for THIS test (which is about CLI
        # behaviour, not response semantics).
        cb_url = f"http://127.0.0.1:{port}/cb?token=tok&state=attacker-state"
        try:
            urllib.request.urlopen(cb_url, timeout=2)
        except (urllib.error.URLError, http.client.RemoteDisconnected, ConnectionError):
            pass

        try:
            _, err = proc.communicate(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
            _, err = proc.communicate()

        assert proc.returncode != 0, "login should reject state mismatch"
        assert "state" in err.lower() or "csrf" in err.lower()

        cfg_path = scratch_home / ".config" / "orchardgrid" / "config.json"
        assert not cfg_path.exists(), "config should NOT be written on state mismatch"
    finally:
        if proc.poll() is None:
            proc.kill()
            proc.communicate()


def test_logout_removes_config(run_og, scratch_home, config_for):
    """`og logout` must delete the saved config file."""
    # Pre-create a config.
    run_og("me", write_config=config_for())  # write_config side effect creates the file
    cfg_path = scratch_home / ".config" / "orchardgrid" / "config.json"
    assert cfg_path.exists(), "precondition: config should exist"

    # Now log out.
    result = run_og("logout")
    assert result.returncode == 0
    assert not cfg_path.exists(), "og logout should have removed the config"
    assert "logged out" in result.stdout.lower()


def test_logout_when_not_logged_in(run_og, scratch_home):
    """`og logout` with no existing config should print a gentle message,
    not crash or error-exit."""
    result = run_og("logout")
    # Exit 0 is fine; exit 1 with a clear message is also fine. Anything
    # else (esp. SIGSEGV) is not.
    assert not result.crashed
    assert result.returncode in (0, 1)
    assert "not logged in" in result.stderr.lower() or result.returncode == 0


def test_logout_revoke_deletes_remote_key(
    run_og, mock_server, config_for, scratch_home
):
    """`og logout --revoke` must DELETE the server-side api_keys row,
    then drop the local config. Regression guard for the "lost laptop"
    scenario — purely-local logout leaves the management token alive."""
    # Config carries a specific keyHint that og logout should send in
    # the DELETE path.
    cfg = config_for(token="tok-rev-test")
    cfg["keyHint"] = "sk-orchard•••REVK"

    mock_server.script_api(
        "DELETE", f"/api/api-keys/{cfg['keyHint']}", body={"success": True}
    )

    result = run_og("logout", "--revoke", write_config=cfg)
    assert result.returncode == 0, result.stderr
    assert "revoked" in result.stdout
    assert "logged out" in result.stdout

    # Server saw the DELETE.
    deletes = mock_server.requests_to("DELETE", f"/api/api-keys/{cfg['keyHint']}")
    assert len(deletes) == 1
    assert deletes[0].headers.get("Authorization") == "Bearer tok-rev-test"

    # Local config is gone.
    cfg_path = scratch_home / ".config" / "orchardgrid" / "config.json"
    assert not cfg_path.exists()


def test_logout_revoke_without_config(run_og, scratch_home):
    """`og logout --revoke` with no saved config should report "nothing to
    revoke" rather than crash or attempt an unauthenticated DELETE."""
    result = run_og("logout", "--revoke")
    assert not result.crashed
    # stderr says nothing-to-revoke; stdout may be empty.
    assert "nothing to revoke" in result.stderr.lower() or "not logged in" in result.stderr.lower()
