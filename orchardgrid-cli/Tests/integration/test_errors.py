"""Exit-code and error-message verification for every HTTP error shape."""

import pytest


@pytest.mark.parametrize(
    "status, type_, message, expected_exit, expected_label",
    [
        (400, "content_policy_violation", "blocked", 3, "[guardrail]"),
        (400, "context_length_exceeded", "too long", 4, "[context overflow]"),
        (401, "authentication_error", "nope", 1, "[error]"),
        (429, "rate_limit_error", "slow down", 6, "[rate limited]"),
        (503, "server_error", "offline", 5, "[model unavailable]"),
        (500, "server_error", "boom", 1, "[error]"),
    ],
)
def test_http_error_maps_to_exit_code(
    run_og, mock_server, status, type_, message, expected_exit, expected_label
):
    mock_server.script_error(status=status, type_=type_, message=message)
    result = run_og("hi")
    assert result.returncode == expected_exit, result.stderr
    assert expected_label in result.stderr


def test_unknown_flag_exits_with_usage(run_og):
    result = run_og("--no-such-flag")
    assert result.returncode == 2
    assert "unknown flag" in result.stderr


def test_invalid_output_format_exits_with_usage(run_og):
    result = run_og("-o", "yaml", "hi")
    assert result.returncode == 2
    assert "invalid value for -o" in result.stderr


def test_invalid_temperature_exits_with_usage(run_og):
    result = run_og("--temperature", "hot", "hi")
    assert result.returncode == 2
    assert "invalid value for --temperature" in result.stderr


def test_missing_value_exits_with_usage(run_og):
    result = run_og("--temperature")
    assert result.returncode == 2
    assert "--temperature requires a value" in result.stderr


def test_server_unreachable(run_og):
    # Point at a port that nothing is listening on.
    result = run_og("hello", host="http://127.0.0.1:1")
    assert result.returncode == 1
    assert "unreachable" in result.stderr.lower()
