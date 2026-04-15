"""Happy-path smoke tests: version, help, model-info, single prompt."""


def test_version(run_og):
    result = run_og("--version")
    assert result.returncode == 0
    assert result.stdout.startswith("og v")


def test_help(run_og):
    result = run_og("--help")
    assert result.returncode == 0
    # Help output lists all top-level subcommands.
    assert "SUBCOMMANDS" in result.stdout
    assert "chat" in result.stdout
    assert "login" in result.stdout
    assert "keys" in result.stdout


def test_no_args_exits_with_usage(run_og):
    # `og` with nothing to do prints help via CleanExit (usage exit code).
    result = run_og()
    # SAP's CleanExit for help/usage uses exit code 0 when help was requested,
    # or 64 for usage errors. Our Run command throws CleanExit.helpRequest,
    # which prints help and exits 0.
    assert result.returncode == 0
    assert "USAGE" in result.stdout or "SUBCOMMANDS" in result.stdout


def test_model_info_reaches_mock_health(run_og, mock_server):
    result = run_og("model-info")
    assert result.returncode == 0
    assert "apple-foundationmodel" in result.stdout
    assert "ok" in result.stdout
    # The server saw exactly one GET /health.
    healths = [r for r in mock_server.config.recorded if r.path == "/health"]
    assert len(healths) == 1


def test_model_info_reports_unavailable_model(run_og, mock_server):
    mock_server.script_health(available=False)
    result = run_og("model-info")
    assert result.returncode == 0
    assert "model unavailable" in result.stdout.lower()


def test_single_prompt_streams_all_deltas(run_og, mock_server):
    mock_server.script_chat(
        deltas=["Hello", ", ", "world", "!"],
        usage={"prompt_tokens": 3, "completion_tokens": 4, "total_tokens": 7},
    )
    result = run_og("say", "hi")
    assert result.returncode == 0
    assert result.stdout.strip() == "Hello, world!"


def test_single_prompt_hits_chat_endpoint_once(run_og, mock_server):
    mock_server.script_chat(deltas=["ok"])
    run_og("ping")
    posts = [r for r in mock_server.config.recorded if r.method == "POST"]
    assert len(posts) == 1
    assert posts[0].path == "/v1/chat/completions"


def test_request_body_has_user_message(run_og, mock_server):
    mock_server.script_chat(deltas=["x"])
    run_og("what is 1+1")
    [post] = [r for r in mock_server.config.recorded if r.method == "POST"]
    body = post.json()
    assert body["stream"] is True
    user_msgs = [m for m in body["messages"] if m["role"] == "user"]
    assert user_msgs == [{"role": "user", "content": "what is 1+1"}]
