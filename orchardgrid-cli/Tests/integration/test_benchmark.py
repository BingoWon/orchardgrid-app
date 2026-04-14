"""`og benchmark` — drives the RemoteEngine N times against the mock server."""

import json


def test_benchmark_runs_against_remote(run_og, mock_server):
    mock_server.script_chat(
        ["Apple", " Silicon", " chips"],
        usage={"prompt_tokens": 4, "completion_tokens": 3, "total_tokens": 7},
    )
    result = run_og("benchmark", "--runs", "2", "--bench-prompt", "hi")
    assert result.returncode == 0, result.stderr
    assert "Summary" in result.stdout
    assert "run 1/2" in result.stdout
    assert "run 2/2" in result.stdout
    chat_calls = [r for r in mock_server.config.recorded if r.path_only == "/v1/chat/completions"]
    assert len(chat_calls) == 2


def test_benchmark_json_output(run_og, mock_server):
    mock_server.script_chat(
        ["a", "b"],
        usage={"prompt_tokens": 1, "completion_tokens": 2, "total_tokens": 3},
    )
    result = run_og("benchmark", "--runs", "2", "-o", "json", "--quiet")
    assert result.returncode == 0, result.stderr
    report = json.loads(result.stdout)
    assert report["runs"] == 2
    for key in ("ttftMs", "totalMs", "tokensPerSec", "outputTokens"):
        assert set(report[key].keys()) == {"min", "median", "p95", "max", "mean"}


def test_benchmark_rejects_zero_runs(run_og):
    result = run_og("benchmark", "--runs", "0")
    assert result.returncode == 2
    assert "invalid" in result.stderr.lower() or "runs" in result.stderr.lower()
