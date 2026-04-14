"""Stdin piping + file attachment behavior."""


def test_stdin_becomes_prompt_when_no_positional(run_og, mock_server):
    mock_server.script_chat(deltas=["ok"])
    run_og(stdin="summarize this text\n")
    [post] = [r for r in mock_server.config.recorded if r.method == "POST"]
    user = [m for m in post.json()["messages"] if m["role"] == "user"][0]
    assert user["content"].strip() == "summarize this text"


def test_stdin_is_appended_when_positional_exists(run_og, mock_server):
    mock_server.script_chat(deltas=["ok"])
    run_og("answer:", stdin="context line one\ncontext line two\n")
    [post] = [r for r in mock_server.config.recorded if r.method == "POST"]
    content = next(m["content"] for m in post.json()["messages"] if m["role"] == "user")
    assert "context line one" in content
    assert "answer:" in content
    # File/stdin content precedes the prompt.
    assert content.index("context line one") < content.index("answer:")


def test_file_content_prepended_to_prompt(run_og, mock_server, tmp_path):
    mock_server.script_chat(deltas=["ok"])
    f = tmp_path / "code.swift"
    f.write_text("func hello() {}\n")
    run_og("-f", str(f), "explain this")
    [post] = [r for r in mock_server.config.recorded if r.method == "POST"]
    content = next(m["content"] for m in post.json()["messages"] if m["role"] == "user")
    assert "func hello() {}" in content
    assert "explain this" in content


def test_multiple_files_joined_with_blank_line(run_og, mock_server, tmp_path):
    mock_server.script_chat(deltas=["ok"])
    a = tmp_path / "a.txt"
    b = tmp_path / "b.txt"
    a.write_text("alpha\n")
    b.write_text("beta\n")
    run_og("-f", str(a), "-f", str(b), "compare")
    [post] = [r for r in mock_server.config.recorded if r.method == "POST"]
    content = next(m["content"] for m in post.json()["messages"] if m["role"] == "user")
    assert "alpha" in content
    assert "beta" in content
    assert "compare" in content


def test_missing_file_exits_with_runtime(run_og):
    result = run_og("-f", "/definitely/does/not/exist.txt", "hi")
    assert result.returncode == 1
    assert "could not read" in result.stderr
