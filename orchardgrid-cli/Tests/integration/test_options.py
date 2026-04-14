"""Request-body parameters: temperature, seed, permissive, context strategy, auth."""

import pytest


def _body(mock_server):
    posts = [r for r in mock_server.config.recorded if r.method == "POST"]
    assert posts, "no POST recorded"
    return posts[-1].json()


def test_temperature_forwarded(run_og, mock_server):
    mock_server.script_chat(deltas=["x"])
    run_og("--temperature", "0.5", "hi")
    assert _body(mock_server)["temperature"] == 0.5


def test_max_tokens_forwarded(run_og, mock_server):
    mock_server.script_chat(deltas=["x"])
    run_og("--max-tokens", "128", "hi")
    assert _body(mock_server)["max_tokens"] == 128


def test_seed_forwarded(run_og, mock_server):
    mock_server.script_chat(deltas=["x"])
    run_og("--seed", "42", "hi")
    assert _body(mock_server)["seed"] == 42


def test_permissive_forwarded(run_og, mock_server):
    mock_server.script_chat(deltas=["x"])
    run_og("--permissive", "hi")
    assert _body(mock_server)["permissive"] is True


def test_permissive_default_omitted(run_og, mock_server):
    mock_server.script_chat(deltas=["x"])
    run_og("hi")
    assert "permissive" not in _body(mock_server)


@pytest.mark.parametrize(
    "strategy", ["newest-first", "oldest-first", "sliding-window", "strict"]
)
def test_context_strategy_forwarded(run_og, mock_server, strategy):
    mock_server.script_chat(deltas=["x"])
    run_og("--context-strategy", strategy, "hi")
    assert _body(mock_server)["context_strategy"] == strategy


def test_context_max_turns_forwarded(run_og, mock_server):
    mock_server.script_chat(deltas=["x"])
    run_og("--context-strategy", "sliding-window", "--context-max-turns", "8", "hi")
    body = _body(mock_server)
    assert body["context_strategy"] == "sliding-window"
    assert body["context_max_turns"] == 8


def test_bearer_token_forwarded_via_flag(run_og, mock_server):
    mock_server.script_chat(deltas=["x"])
    run_og("--token", "s3cret", "hi")
    posts = [r for r in mock_server.config.recorded if r.method == "POST"]
    auth = posts[-1].headers.get("Authorization")
    assert auth == "Bearer s3cret"


def test_bearer_token_forwarded_via_env(run_og, mock_server):
    mock_server.script_chat(deltas=["x"])
    run_og("hi", env_extra={"ORCHARDGRID_TOKEN": "envsek"})
    posts = [r for r in mock_server.config.recorded if r.method == "POST"]
    auth = posts[-1].headers.get("Authorization")
    assert auth == "Bearer envsek"


def test_no_token_no_auth_header(run_og, mock_server):
    mock_server.script_chat(deltas=["x"])
    # Clear any inherited token env in the parent process (from shell profiles).
    run_og("hi", env_extra={"ORCHARDGRID_TOKEN": ""})
    posts = [r for r in mock_server.config.recorded if r.method == "POST"]
    auth = posts[-1].headers.get("Authorization")
    assert auth is None or auth == "Bearer "
