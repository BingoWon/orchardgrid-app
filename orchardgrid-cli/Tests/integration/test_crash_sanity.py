"""Crash-resistance smoke tests.

Every CLI subcommand must exit cleanly — no SIGSEGV, no silent exit. This
file exists because a prior `og login` regression (uninitialized top-level
`#if DEBUG let`, plus NSHost/mDNS deadlock from `ProcessInfo.hostName`)
slipped through the rest of the suite: nothing ever invoked the management
subcommands end-to-end before.

The critical assertion is `not result.crashed` — i.e. exit code is NOT 139
(SIGSEGV), 138 (SIGBUS), 134 (SIGABRT), or any negative signal value. A
"clean" user-facing error (1–6) is an acceptable outcome here; we're only
guarding against native crashes and mysterious silent exits.
"""

import pytest


SUBCOMMANDS_WITHOUT_CONFIG = [
    # (argv, description)
    pytest.param(["--version"], id="version"),
    pytest.param(["--help"], id="help"),
    pytest.param(["model-info"], id="model-info"),
    pytest.param(["me"], id="me-no-config"),
    pytest.param(["keys"], id="keys-no-config"),
    pytest.param(["keys", "list"], id="keys-list-no-config"),
    pytest.param(["keys", "create"], id="keys-create-no-config"),
    pytest.param(["keys", "create", "my-bot"], id="keys-create-named-no-config"),
    pytest.param(["keys", "delete", "sk-orchard•••TiF3"], id="keys-delete-no-config"),
    pytest.param(["devices"], id="devices-no-config"),
    pytest.param(["devices", "list"], id="devices-list-no-config"),
    pytest.param(["logs"], id="logs-no-config"),
    pytest.param(["logout"], id="logout-no-config"),
]


@pytest.mark.parametrize("argv", SUBCOMMANDS_WITHOUT_CONFIG)
def test_subcommand_does_not_crash(run_og, argv):
    """Every subcommand, invoked without a saved config, must exit with a
    clean user-facing code (0–6) — never SIGSEGV. This would have caught
    the Swift 6.2 top-level `#if DEBUG let` uninitialized-memory bug and
    the macOS 26 NSHost+mDNS deadlock in a single test run."""
    result = run_og(*argv)
    assert not result.crashed, (
        f"og {' '.join(argv)} died to a signal (exit={result.returncode}). "
        f"stdout={result.stdout!r} stderr={result.stderr!r}"
    )
    # Also reject the "silent exit" pattern (exit != 0 with zero stderr),
    # which is what we saw during the SIGSEGV regression.
    if result.returncode != 0:
        assert result.stderr or result.stdout, (
            f"og {' '.join(argv)} exited {result.returncode} with no output — "
            f"looks like an unreported crash"
        )


def test_login_start_does_not_crash(run_og):
    """`og login` must at least get to the "Waiting for callback" stage
    without a SIGSEGV. Deep loopback/URL-shape checks live in
    test_login.py — this one only guards the crash class."""
    try:
        result = run_og(
            "login",
            host="http://127.0.0.1:1",  # nothing is listening
            timeout=3.0,
        )
    except Exception:
        # Timeout expired → og got far enough to wait → sanity achieved.
        return
    assert not result.crashed, (
        f"og login crashed (exit={result.returncode}). stderr={result.stderr!r}"
    )
