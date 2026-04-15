# `og` CLI reference

Complete flag, subcommand, environment-variable, and exit-code reference for the `og` binary. Run `og --help` for the same content in terminal form.

---

## Synopsis

```
og [OPTIONS] <prompt>            # single prompt, streamed to stdout
og --chat                        # interactive REPL
og --model-info                  # model availability, source, context size
og <subcommand> [args]           # account / diagnostic commands
```

## Modes

| Invocation | Backend | Requires |
|---|---|---|
| `og "prompt"` | `LocalEngine` — `SystemLanguageModel.default` in-process | Apple Silicon + macOS 26 + Apple Intelligence enabled |
| `og --host http://mac.local:8888 "prompt"` | `RemoteEngine` — HTTP to a LAN peer | Peer reachable |
| `og --host https://orchardgrid.com --token sk-… "prompt"` | `RemoteEngine` — cloud relay | API key |

## Options

| Flag | Type | Default | Description |
|---|---|---|---|
| `-f`, `--file <path>` | string (repeatable) | — | Attach file content to the prompt |
| `-s`, `--system <text>` | string | — | System prompt |
| `--system-file <path>` | path | — | Read system prompt from a file |
| `-o`, `--output <fmt>` | `plain` / `json` | `plain` | Output format |
| `-q`, `--quiet` | flag | off | Suppress chrome (headers, prompts, banners) |
| `--no-color` | flag | off | Disable ANSI colour |
| `--temperature <n>` | double | — | Sampling temperature (passes through to model) |
| `--max-tokens <n>` | int | — | Cap completion length |
| `--seed <n>` | uint64 | — | Random seed for reproducibility |
| `--context-strategy <s>` | enum | `newest-first` | See [context-strategies.md](context-strategies.md) |
| `--context-max-turns <n>` | int | — | Max turns for `sliding-window` |
| `--permissive` | flag | off | Relax safety guardrails |
| `--host <url>` | url | — | Remote OrchardGrid host (disables on-device) |
| `--token <secret>` | string | — | Bearer token for `--host` |
| `--mcp <path>` | path (repeatable) | — | Attach an MCP server (on-device only) |
| `--mcp-timeout <s>` | int | 5 | Per-request MCP timeout |
| `--runs <n>` | int | 5 | `og benchmark` sample count |
| `--bench-prompt <text>` | string | built-in | `og benchmark` prompt |
| `--role <r>` | enum | — | `og logs` filter: `consumer` / `provider` / `self` |
| `--status <s>` | string | — | `og logs` status filter |
| `--limit <n>` | int | 50 | Page size for `og logs` |
| `--offset <n>` | int | 0 | Page offset for `og logs` |
| `--name <text>` | string | — | Name for `og keys create` |
| `--revoke` | flag | off | `og logout --revoke` — also revoke server-side |
| `-h`, `--help` | flag | — | Show help |
| `-v`, `--version` | flag | — | Print `og <version> (<commit>, <date>)` |

## Subcommands

### Account (require `og login` first)

| Command | Purpose |
|---|---|
| `og login` | OAuth loopback; opens browser, issues a management-scope API key |
| `og logout` | Drop local creds |
| `og logout --revoke` | … and revoke the key server-side |
| `og me` | Account info |
| `og keys` · `og keys list` | List API keys |
| `og keys create [--name N]` | New inference-scope key (printed once) |
| `og keys delete <hint>` | Revoke an inference key |
| `og devices` | List your devices |
| `og logs [--role R] [--status S] [--limit N] [--offset M]` | Recent usage |

### Local snapshot

| Command | Purpose |
|---|---|
| `og status` | Local server state, sharing toggles, login state |

### Diagnostics

| Command | Purpose |
|---|---|
| `og benchmark [--runs N] [--bench-prompt "…"]` | ttft / total / tokens/sec (respects `--temperature` / `--max-tokens`) |
| `og mcp list <path> [<path>…]` | Introspect an MCP server without running inference |

## Environment variables

| Variable | Meaning |
|---|---|
| `ORCHARDGRID_HOST` | Default remote host (unset → on-device) |
| `ORCHARDGRID_TOKEN` | Default bearer token |
| `OG_NO_BROWSER` | `og login` skips auto browser launch (SSH / CI) |
| `NO_COLOR` | Disable ANSI colour |

## Exit codes

| Code | Meaning |
|:---:|---|
| 0 | Success |
| 1 | Runtime error (network, auth, unreachable) |
| 2 | Usage error (bad flag, conflicting options) |
| 3 | Guardrail blocked |
| 4 | Context overflow |
| 5 | Model unavailable (Apple Intelligence not enabled) |
| 6 | Rate limited |

## Reading order

- **Context trimming in depth** → [context-strategies.md](context-strategies.md)
- **OpenAI compatibility matrix** → [openai-api-compatibility.md](openai-api-compatibility.md)
- **CLI architecture + tests** → [../orchardgrid-cli/README.md](../orchardgrid-cli/README.md)
