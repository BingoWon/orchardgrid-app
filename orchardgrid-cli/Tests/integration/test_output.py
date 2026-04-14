"""Output format: plain streaming vs JSON envelope."""

import json


def test_plain_output_streams_deltas(run_og, mock_server):
    mock_server.script_chat(deltas=["Hello", " world"])
    result = run_og("hi")
    assert result.returncode == 0
    # Plain mode writes deltas and finishes with a newline.
    assert result.stdout == "Hello world\n"


def test_json_output_emits_envelope(run_og, mock_server):
    mock_server.script_chat(
        deltas=["Hello"],
        usage={"prompt_tokens": 2, "completion_tokens": 3, "total_tokens": 5},
    )
    result = run_og("-o", "json", "hi")
    assert result.returncode == 0
    doc = json.loads(result.stdout)
    assert doc["content"] == "Hello"
    assert doc["usage"] == {
        "prompt_tokens": 2,
        "completion_tokens": 3,
        "total_tokens": 5,
    }


def test_json_output_handles_missing_usage(run_og, mock_server):
    mock_server.script_chat(deltas=["Hi"])  # no usage
    result = run_og("-o", "json", "hi")
    assert result.returncode == 0
    doc = json.loads(result.stdout)
    assert doc["content"] == "Hi"
    assert "usage" not in doc


def test_no_color_env_suppresses_ansi(run_og, mock_server):
    mock_server.script_chat(deltas=["plain"])
    result = run_og("hi", env_extra={"NO_COLOR": "1"})
    assert "\x1b[" not in result.stdout


def test_system_prompt_flag(run_og, mock_server):
    mock_server.script_chat(deltas=["ok"])
    run_og("-s", "be brief", "hi")
    [post] = [r for r in mock_server.config.recorded if r.method == "POST"]
    messages = post.json()["messages"]
    assert messages[0] == {"role": "system", "content": "be brief"}
    assert any(m["role"] == "user" for m in messages)


def test_system_file_flag(run_og, mock_server, tmp_path):
    mock_server.script_chat(deltas=["ok"])
    f = tmp_path / "sys.txt"
    f.write_text("you are a poet\n")
    run_og("--system-file", str(f), "hi")
    [post] = [r for r in mock_server.config.recorded if r.method == "POST"]
    system = next(m for m in post.json()["messages"] if m["role"] == "system")
    assert system["content"] == "you are a poet"
