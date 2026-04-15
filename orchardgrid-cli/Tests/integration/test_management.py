"""End-to-end tests for management subcommands: me / keys / devices / logs.

Each test writes a fresh config.json into a scratch HOME pointing at the
mock server, then invokes `og <subcommand>` and asserts the subcommand:
1. sends the right request (method, path, Bearer header)
2. formats the response sensibly for stdout
3. surfaces errors via the documented exit codes
"""

from __future__ import annotations

import pytest


# ---------------------------------------------------------------------------
# og me
# ---------------------------------------------------------------------------


def test_me_hits_api_and_prints_user(run_og, mock_server, config_for):
    mock_server.script_api(
        "GET", "/api/me", body={"id": "user_test123", "isAdmin": True}
    )
    result = run_og("me", write_config=config_for())
    assert result.returncode == 0
    assert "user_test123" in result.stdout
    assert "yes" in result.stdout

    [req] = mock_server.requests_to("GET", "/api/me")
    assert req.headers.get("Authorization") == "Bearer test-management-token"


def test_me_without_config_errors_cleanly(run_og):
    """Without a saved config and no --token, og me must say "run og login",
    not crash."""
    result = run_og("me")
    assert not result.crashed
    assert result.returncode == 1
    assert "og login" in result.stderr


def test_me_401_suggests_relogin(run_og, mock_server, config_for):
    mock_server.script_api(
        "GET",
        "/api/me",
        status=401,
        body={"error": {"message": "stale", "type": "authentication_error"}},
    )
    result = run_og("me", write_config=config_for())
    assert result.returncode == 1
    assert "og login" in result.stderr


def test_me_403_suggests_management_scope(run_og, mock_server, config_for):
    mock_server.script_api(
        "GET",
        "/api/me",
        status=403,
        body={"error": {"message": "forbidden", "type": "permission_error"}},
    )
    result = run_og("me", write_config=config_for())
    assert result.returncode == 1
    assert "management" in result.stderr.lower()


# ---------------------------------------------------------------------------
# og keys …
# ---------------------------------------------------------------------------


def test_keys_list_empty(run_og, mock_server, config_for):
    mock_server.script_api("GET", "/api/api-keys", body={"keys": []})
    result = run_og("keys", "list", write_config=config_for())
    assert result.returncode == 0
    assert "no API keys" in result.stdout


def test_keys_list_formats_table(run_og, mock_server, config_for):
    mock_server.script_api(
        "GET",
        "/api/api-keys",
        body={
            "keys": [
                {
                    "key_hint": "sk-orchard•••ab12",
                    "name": "my-bot",
                    "scope": "inference",
                    "device_label": None,
                    "created_at": 1_700_000_000_000,
                    "last_used_at": 1_700_000_100_000,
                },
                {
                    "key_hint": "sk-orchard•••xy99",
                    "name": "og @ TestMac",
                    "scope": "management",
                    "device_label": "TestMac",
                    "created_at": 1_700_000_200_000,
                    "last_used_at": None,
                },
            ]
        },
    )
    result = run_og("keys", write_config=config_for())  # default is list
    assert result.returncode == 0
    assert "my-bot" in result.stdout
    assert "og @ TestMac" in result.stdout
    assert "management" in result.stdout
    assert "inference" in result.stdout
    # Hint column shows masked keys.
    assert "ab12" in result.stdout
    assert "xy99" in result.stdout


def test_keys_create_named(run_og, mock_server, config_for):
    mock_server.script_api(
        "POST",
        "/api/api-keys",
        body={
            "key": "sk-orchardgrid-PLAINTEXT-secret",
            "key_hint": "sk-orchard•••cret",
            "name": "my-bot",
            "scope": "inference",
            "device_label": None,
            "created_at": 1_700_000_000_000,
            "last_used_at": None,
        },
    )
    result = run_og("keys", "create", "my-bot", write_config=config_for())
    assert result.returncode == 0
    assert "sk-orchardgrid-PLAINTEXT-secret" in result.stdout
    assert "won't see it again" in result.stdout
    assert "my-bot" in result.stdout

    [req] = mock_server.requests_to("POST", "/api/api-keys")
    body = req.json()
    assert body["name"] == "my-bot"
    assert body["scope"] == "inference"


def test_keys_create_sends_inference_scope_by_default(
    run_og, mock_server, config_for
):
    """`og keys create` defaults to inference scope — management-scope keys
    are issued only by the /cli/login flow."""
    mock_server.script_api(
        "POST",
        "/api/api-keys",
        body={
            "key": "sk-plain",
            "key_hint": "sk-••••plain",
            "name": None,
            "scope": "inference",
            "device_label": None,
            "created_at": 1,
            "last_used_at": None,
        },
    )
    run_og("keys", "create", write_config=config_for())
    [req] = mock_server.requests_to("POST", "/api/api-keys")
    assert req.json()["scope"] == "inference"


def test_keys_delete_sends_hint_in_path(run_og, mock_server, config_for):
    hint = "sk-orchard••••••TiF3"
    mock_server.script_api("DELETE", f"/api/api-keys/{hint}", body={"success": True})
    result = run_og("keys", "delete", hint, write_config=config_for())
    assert result.returncode == 0
    assert "deleted" in result.stdout.lower()

    requests = [
        r for r in mock_server.config.recorded if r.method == "DELETE"
    ]
    assert len(requests) == 1, f"expected 1 DELETE, saw {requests}"
    # Server-side Hono decodes the path, so the recorded path has the raw
    # hint re-encoded by Python's URL library — just check the bullet made
    # the round trip.
    assert "TiF3" in requests[0].path_only
    assert "••••••" in requests[0].path_only or "%E2%80%A2" in requests[0].path


def test_keys_delete_without_hint_errors(run_og, scratch_home):
    result = run_og("keys", "delete")
    assert not result.crashed
    assert result.returncode == 64  # BSD EX_USAGE for missing required argument
    assert "hint" in result.stderr.lower() or "missing" in result.stderr.lower()


def test_keys_delete_404(run_og, mock_server, config_for):
    mock_server.script_api(
        "DELETE",
        "/api/api-keys/sk-orchard•••nope",
        status=404,
        body={"error": {"message": "API key not found", "type": "not_found_error"}},
    )
    result = run_og("keys", "delete", "sk-orchard•••nope", write_config=config_for())
    assert result.returncode == 1
    assert "not found" in result.stderr.lower()


# ---------------------------------------------------------------------------
# og devices
# ---------------------------------------------------------------------------


def test_devices_list_empty(run_og, mock_server, config_for):
    mock_server.script_api("GET", "/api/devices", body=[])
    result = run_og("devices", write_config=config_for())
    assert result.returncode == 0
    assert "no devices" in result.stdout.lower()


def test_devices_list_with_one_device(run_og, mock_server, config_for):
    mock_server.script_api(
        "GET",
        "/api/devices",
        body=[
            {
                "id": "dev_abc",
                "platform": "macOS",
                "device_name": "Bin's Mac mini",
                "chip_model": "Apple M2 Pro",
                "is_online": True,
                "last_heartbeat": 1_700_000_000_000,
                "logs_processed": 42,
                "capabilities": ["chat", "image"],
            }
        ],
    )
    result = run_og("devices", write_config=config_for())
    assert result.returncode == 0
    assert "online" in result.stdout
    assert "macOS" in result.stdout
    assert "Bin" in result.stdout  # device name (apostrophe may mangle — substr check)
    assert "42" in result.stdout


# ---------------------------------------------------------------------------
# og logs
# ---------------------------------------------------------------------------


def test_logs_empty(run_og, mock_server, config_for):
    mock_server.script_api(
        "GET", "/api/logs", body={"logs": [], "total": 0, "limit": 50, "offset": 0}
    )
    result = run_og("logs", write_config=config_for())
    assert result.returncode == 0
    assert "no logs" in result.stdout.lower()


def test_logs_with_flags_forwards_query(run_og, mock_server, config_for):
    mock_server.script_api(
        "GET",
        "/api/logs",
        body={
            "logs": [
                {
                    "id": "log_1",
                    "capability": "chat",
                    "status": "completed",
                    "role": "self",
                    "prompt_tokens": 10,
                    "completion_tokens": 20,
                    "created_at": 1_700_000_000_000,
                    "duration_ms": 1234,
                }
            ],
            "total": 1,
            "limit": 5,
            "offset": 10,
        },
    )
    result = run_og(
        "logs",
        "--role",
        "self",
        "--status",
        "completed",
        "--limit",
        "5",
        "--offset",
        "10",
        write_config=config_for(),
    )
    assert result.returncode == 0
    assert "chat" in result.stdout
    assert "completed" in result.stdout

    [req] = mock_server.requests_to("GET", "/api/logs")
    assert req.query.get("role") == ["self"]
    assert req.query.get("status") == ["completed"]
    assert req.query.get("limit") == ["5"]
    assert req.query.get("offset") == ["10"]


# ---------------------------------------------------------------------------
# Auth headers across all management commands
# ---------------------------------------------------------------------------


@pytest.mark.parametrize(
    "argv, route",
    [
        (["me"], ("GET", "/api/me")),
        (["keys"], ("GET", "/api/api-keys")),
        (["devices"], ("GET", "/api/devices")),
        (["logs"], ("GET", "/api/logs")),
    ],
)
def test_all_management_commands_send_bearer(
    run_og, mock_server, config_for, argv, route
):
    method, path = route
    # Give each route a trivial-but-well-formed body.
    bodies = {
        "/api/me": {"id": "u", "isAdmin": False},
        "/api/api-keys": {"keys": []},
        "/api/devices": [],
        "/api/logs": {"logs": [], "total": 0, "limit": 50, "offset": 0},
    }
    mock_server.script_api(method, path, body=bodies[path])

    result = run_og(*argv, write_config=config_for(token="xyz-secret"))
    assert result.returncode == 0

    [req] = mock_server.requests_to(method, path)
    assert req.headers.get("Authorization") == "Bearer xyz-secret"
