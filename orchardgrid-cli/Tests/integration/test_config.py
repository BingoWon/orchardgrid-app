"""Config-file lifecycle + host/token resolution priority.

Subprocess-level complement to ConfigTests.swift — proves that the priority
chain (flag > env > config > build-time default) holds when observed from
the outside, not just inside the Swift unit test.
"""

import json


def test_config_token_used_by_management_commands(
    run_og, mock_server, config_for
):
    """Management commands read token from config.json when no --token is passed."""
    mock_server.script_api("GET", "/api/me", body={"id": "u", "isAdmin": False})
    run_og("me", write_config=config_for(token="tok-from-config"))

    [req] = mock_server.requests_to("GET", "/api/me")
    assert req.headers.get("Authorization") == "Bearer tok-from-config"


def test_explicit_token_beats_config(run_og, mock_server, config_for):
    mock_server.script_api("GET", "/api/me", body={"id": "u", "isAdmin": False})
    run_og(
        "me",
        "--token",
        "tok-from-flag",
        write_config=config_for(token="tok-from-config"),
    )
    [req] = mock_server.requests_to("GET", "/api/me")
    assert req.headers.get("Authorization") == "Bearer tok-from-flag"


def test_env_token_beats_config(run_og, mock_server, config_for):
    mock_server.script_api("GET", "/api/me", body={"id": "u", "isAdmin": False})
    run_og(
        "me",
        env_extra={"ORCHARDGRID_TOKEN": "tok-from-env"},
        write_config=config_for(token="tok-from-config"),
    )
    [req] = mock_server.requests_to("GET", "/api/me")
    assert req.headers.get("Authorization") == "Bearer tok-from-env"


def test_explicit_host_beats_config(run_og, mock_server, config_for, scratch_home):
    """`og me --host <mock>` should hit the mock even if config.json points
    at a dead host."""
    mock_server.script_api("GET", "/api/me", body={"id": "u", "isAdmin": False})
    # Config points at a dead port.
    cfg_path = scratch_home / ".config" / "orchardgrid"
    cfg_path.mkdir(parents=True, exist_ok=True)
    (cfg_path / "config.json").write_text(
        json.dumps(
            {
                "host": "http://127.0.0.1:1",  # dead
                "token": "tok",
                "keyHint": "…",
                "deviceLabel": "x",
            }
        )
    )
    # Explicit --host must win.
    result = run_og("me", "--host", mock_server.url)
    assert result.returncode == 0, result.stderr
    [req] = mock_server.requests_to("GET", "/api/me")
    assert req.headers.get("Authorization") == "Bearer tok"


def test_config_host_does_not_leak_to_inference(
    run_og, mock_server, config_for
):
    """THIS is the architectural invariant we manually validated:
    a saved config's host applies ONLY to management commands. A chat
    request (`og "prompt"`) must NOT route through config.host, because
    that would silently hijack on-device inference to HTTP.

    With config.host = mock_server.url and no --host flag, `og "hi"`
    should go to on-device FoundationModels — which on CI / macOS<26
    means "never hit the mock server at all". We assert that the mock
    saw zero /v1/chat/completions requests.

    (On macOS 26 with Apple Intelligence enabled, the request actually
    succeeds on-device. Either way, the mock must not be touched.)
    """
    import subprocess as _sp

    # Ensure no stale scripting confuses things.
    mock_server.script_chat(deltas=["should-never-be-streamed"])
    mock_server.clear_recorded()

    # run_og's fixture sets ORCHARDGRID_HOST to the mock URL by default —
    # that itself would route inference to the mock. Clear it so we're
    # genuinely testing "no explicit host, only config.json present".
    try:
        run_og(
            "hello",
            write_config=config_for(),
            env_extra={"ORCHARDGRID_HOST": ""},
            timeout=3.0,
        )
    except _sp.TimeoutExpired:
        pass  # on-device inference taking longer than 3 s is fine — we kill it

    chat_requests = mock_server.requests_to("POST", "/v1/chat/completions")
    assert chat_requests == [], (
        "config.host leaked into inference path — `og 'hi'` hit the mock "
        "/v1/chat/completions even though no --host was specified"
    )


def test_explicit_host_routes_inference_to_remote(
    run_og, mock_server
):
    """Dual of the above: when --host IS specified, inference goes through HTTP."""
    mock_server.script_chat(deltas=["remote-ok"])
    result = run_og("hi", "--host", mock_server.url)
    assert result.returncode == 0
    assert "remote-ok" in result.stdout

    chat_requests = mock_server.requests_to("POST", "/v1/chat/completions")
    assert len(chat_requests) == 1
