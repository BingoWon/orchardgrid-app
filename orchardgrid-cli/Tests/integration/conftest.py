"""Pytest fixtures for the og CLI integration suite.

Launches a mock HTTP server on an ephemeral port and wires `og` invocations
to it via `ORCHARDGRID_HOST`. Zero external deps — only Python stdlib.
"""

from __future__ import annotations

import json
import os
import subprocess
import threading
from dataclasses import dataclass, field
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any, Callable, Iterator
from urllib.parse import parse_qs, unquote, urlsplit

import pytest

# ----------------------------------------------------------------------------
# Binary discovery
# ----------------------------------------------------------------------------

REPO_ROOT = Path(__file__).resolve().parents[2]
OG_BINARY = REPO_ROOT / ".build" / "release" / "og"
OG_BINARY_DEBUG = REPO_ROOT / ".build" / "debug" / "og"


def _resolve_og() -> Path:
    for candidate in (OG_BINARY, OG_BINARY_DEBUG):
        if candidate.exists():
            return candidate
    pytest.exit(
        f"og binary not found. Run `swift build -c release` in {REPO_ROOT}.",
        returncode=2,
    )


# ----------------------------------------------------------------------------
# Mock server
# ----------------------------------------------------------------------------


@dataclass
class Recorded:
    """A single request the mock server observed."""

    method: str
    path: str
    headers: dict[str, str]
    body: bytes

    def json(self) -> dict:
        return json.loads(self.body) if self.body else {}

    @property
    def path_only(self) -> str:
        """URL-decoded path — so tests can register routes using raw
        non-ASCII hints (e.g. the bullet-masked api_keys suffix) without
        worrying about UTF-8 percent encoding on the wire."""
        return unquote(urlsplit(self.path).path)

    @property
    def query(self) -> dict[str, list[str]]:
        return parse_qs(urlsplit(self.path).query)


# Handlers are plain callables: (handler, recorded_request) -> (status, body_bytes)
Handler = Callable[[Any, Recorded], tuple[int, bytes]]


@dataclass
class MockConfig:
    """Shared state between the server handler and the test."""

    health: dict = field(
        default_factory=lambda: {
            "status": "ok",
            "model": "apple-intelligence",
            "available": True,
        }
    )
    sse_chunks: list[dict] = field(default_factory=list)
    error_status: int | None = None
    error_type: str = ""
    error_message: str = ""
    # Management-plane overrides: (method, path) -> (status, JSON-serialisable body)
    json_routes: dict[tuple[str, str], tuple[int, Any]] = field(default_factory=dict)
    recorded: list[Recorded] = field(default_factory=list)


class MockServer:
    """A thread-backed HTTP server that speaks OrchardGrid's API shape."""

    def __init__(self) -> None:
        self.config = MockConfig()
        self._server = ThreadingHTTPServer(("127.0.0.1", 0), self._make_handler())
        self.port = self._server.server_address[1]
        self._thread = threading.Thread(target=self._server.serve_forever, daemon=True)

    # Public control surface ---------------------------------------------------

    def start(self) -> None:
        self._thread.start()

    def stop(self) -> None:
        self._server.shutdown()
        self._server.server_close()
        self._thread.join(timeout=5)

    @property
    def url(self) -> str:
        return f"http://127.0.0.1:{self.port}"

    # Declarative scripting ----------------------------------------------------

    def script_chat(
        self,
        deltas: list[str],
        usage: dict | None = None,
    ) -> None:
        """Queue an SSE stream that emits `deltas` then a usage-bearing end frame."""
        chunks: list[dict] = []
        for delta in deltas:
            chunks.append({"choices": [{"delta": {"content": delta}}]})
        end: dict = {"choices": [{"delta": {"content": ""}, "finish_reason": "stop"}]}
        if usage is not None:
            end["usage"] = usage
        chunks.append(end)
        self.config.sse_chunks = chunks
        self.config.error_status = None

    def script_error(self, status: int, type_: str, message: str) -> None:
        self.config.error_status = status
        self.config.error_type = type_
        self.config.error_message = message
        self.config.sse_chunks = []

    def script_health(self, **fields) -> None:
        self.config.health.update(fields)

    def script_api(self, method: str, path: str, status: int = 200, body: Any = None) -> None:
        """Register a JSON response for an /api/* management route."""
        self.config.json_routes[(method.upper(), path)] = (status, body)

    def clear_recorded(self) -> None:
        self.config.recorded.clear()

    def requests_to(self, method: str, path: str) -> list[Recorded]:
        return [
            r
            for r in self.config.recorded
            if r.method == method.upper() and r.path_only == path
        ]

    # Handler factory ----------------------------------------------------------

    def _make_handler(self):
        config = self.config

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *_args, **_kwargs):
                pass  # silence default stderr chatter

            def _record(self, body: bytes) -> None:
                config.recorded.append(
                    Recorded(
                        method=self.command,
                        path=self.path,
                        headers={k: v for k, v in self.headers.items()},
                        body=body,
                    )
                )

            def _write_json(self, status: int, payload: Any) -> None:
                data = json.dumps(payload).encode()
                self.send_response(status)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)

            def _dispatch_management(self, record: Recorded) -> bool:
                """Try to match against scripted /api/* routes. Returns True if handled."""
                key = (record.method, record.path_only)
                if key not in config.json_routes:
                    return False
                status, body = config.json_routes[key]
                self._write_json(status, body)
                return True

            def do_OPTIONS(self) -> None:  # noqa: N802
                self._record(b"")
                self.send_response(204)
                self.send_header("Access-Control-Allow-Origin", "*")
                self.end_headers()

            def do_GET(self) -> None:  # noqa: N802
                rec = Recorded(
                    method="GET",
                    path=self.path,
                    headers={k: v for k, v in self.headers.items()},
                    body=b"",
                )
                config.recorded.append(rec)

                if rec.path_only == "/health":
                    self._write_json(200, config.health)
                    return
                if self._dispatch_management(rec):
                    return
                self.send_error(404)

            def do_POST(self) -> None:  # noqa: N802
                length = int(self.headers.get("Content-Length", "0"))
                body = self.rfile.read(length) if length > 0 else b""
                rec = Recorded(
                    method="POST",
                    path=self.path,
                    headers={k: v for k, v in self.headers.items()},
                    body=body,
                )
                config.recorded.append(rec)

                if rec.path_only == "/v1/chat/completions":
                    self._serve_chat()
                    return
                if self._dispatch_management(rec):
                    return
                self.send_error(404)

            def do_PATCH(self) -> None:  # noqa: N802
                length = int(self.headers.get("Content-Length", "0"))
                body = self.rfile.read(length) if length > 0 else b""
                rec = Recorded(
                    method="PATCH",
                    path=self.path,
                    headers={k: v for k, v in self.headers.items()},
                    body=body,
                )
                config.recorded.append(rec)
                if self._dispatch_management(rec):
                    return
                self.send_error(404)

            def do_DELETE(self) -> None:  # noqa: N802
                rec = Recorded(
                    method="DELETE",
                    path=self.path,
                    headers={k: v for k, v in self.headers.items()},
                    body=b"",
                )
                config.recorded.append(rec)
                if self._dispatch_management(rec):
                    return
                self.send_error(404)

            # ── /v1/chat/completions ──────────────────────────────────────

            def _serve_chat(self) -> None:
                if config.error_status is not None:
                    envelope = {
                        "error": {
                            "message": config.error_message,
                            "type": config.error_type,
                        }
                    }
                    self._write_json(config.error_status, envelope)
                    return

                self.send_response(200)
                self.send_header("Content-Type", "text/event-stream")
                self.send_header("Cache-Control", "no-cache")
                self.end_headers()
                for chunk in config.sse_chunks:
                    line = f"data: {json.dumps(chunk)}\n\n".encode()
                    self.wfile.write(line)
                    self.wfile.flush()
                self.wfile.write(b"data: [DONE]\n\n")
                self.wfile.flush()

        return Handler


# ----------------------------------------------------------------------------
# Fixtures
# ----------------------------------------------------------------------------


@pytest.fixture(scope="session")
def og_binary() -> Path:
    return _resolve_og()


@pytest.fixture
def mock_server() -> Iterator[MockServer]:
    server = MockServer()
    server.start()
    try:
        yield server
    finally:
        server.stop()


@pytest.fixture
def scratch_home(tmp_path: Path) -> Path:
    """A clean $HOME for each test — no pollution of the user's real config."""
    home = tmp_path / "home"
    home.mkdir()
    return home


@dataclass
class OGResult:
    returncode: int
    stdout: str
    stderr: str

    @property
    def crashed(self) -> bool:
        """True if the process died to a signal (returncode < 0 on POSIX)."""
        return self.returncode < 0 or self.returncode in (139, 138, 134)


@pytest.fixture
def run_og(og_binary: Path, mock_server: MockServer, scratch_home: Path):
    """Return a callable that invokes og against the mock server."""

    def _run(
        *args: str,
        stdin: str | None = None,
        env_extra: dict[str, str] | None = None,
        host: str | None = None,
        write_config: dict | None = None,
        timeout: float = 10.0,
    ) -> OGResult:
        env = os.environ.copy()
        env["HOME"] = str(scratch_home)
        # Always route to the mock server unless a test overrides the host.
        env["ORCHARDGRID_HOST"] = host or mock_server.url
        env["NO_COLOR"] = "1"
        # Suppress `/usr/bin/open` during tests — otherwise `og login` would
        # spam real browser tabs for every test that touches the login flow.
        env["OG_NO_BROWSER"] = "1"
        if env_extra:
            env.update(env_extra)

        if write_config is not None:
            cfg_dir = scratch_home / ".config" / "orchardgrid"
            cfg_dir.mkdir(parents=True, exist_ok=True)
            (cfg_dir / "config.json").write_text(json.dumps(write_config))

        proc = subprocess.run(
            [str(og_binary), *args],
            input=stdin,
            capture_output=True,
            text=True,
            env=env,
            timeout=timeout,
        )
        return OGResult(
            returncode=proc.returncode,
            stdout=proc.stdout,
            stderr=proc.stderr,
        )

    return _run


@pytest.fixture
def config_for(mock_server: MockServer) -> Callable[[str], dict]:
    """Return a helper that builds a config.json dict pointing at the mock server."""

    def _build(token: str = "test-management-token", device: str = "TestMac") -> dict:
        return {
            "host": mock_server.url,
            "token": token,
            "keyHint": f"{token[:20]}…",
            "deviceLabel": device,
        }

    return _build
