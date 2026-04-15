"""MCP end-to-end tests — spawn the calculator server and introspect it."""

import json
from pathlib import Path

CALC = Path(__file__).parent / "mcp" / "calculator.py"


def test_mcp_list_plain(run_og):
    result = run_og("mcp", "list", str(CALC))
    assert result.returncode == 0, result.stderr
    assert "add" in result.stdout
    assert "Add two integers" in result.stdout


def test_mcp_list_json(run_og):
    result = run_og("mcp", "list", str(CALC), "-o", "json")
    assert result.returncode == 0, result.stderr
    payload = json.loads(result.stdout)
    assert isinstance(payload, list) and len(payload) == 1
    assert payload[0]["name"] == "add"
    schema = json.loads(payload[0]["inputSchema"])
    assert schema["properties"]["a"]["type"] == "integer"
    assert schema["required"] == ["a", "b"]


def test_mcp_list_requires_path(run_og):
    result = run_og("mcp", "list")
    assert result.returncode == 2
    assert "server path" in result.stderr


def test_mcp_requires_local_engine(run_og, mock_server):
    """--mcp + --host is rejected: RemoteEngine can't host tool calls."""
    # `--host` is inherited from the mock_server fixture environment.
    result = run_og(
        "--mcp", str(CALC),
        "hello",
    )
    assert result.returncode == 2
    assert "on-device" in result.stderr
