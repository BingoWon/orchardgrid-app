# og — OrchardGrid CLI

Apple's built-in AI from the command line. Runs **on-device FoundationModels
directly in-process** — no GUI app required, no local HTTP hop. Pass
`--host` to talk to a LAN peer or the OrchardGrid cloud instead.

```sh
brew install --cask bingowon/orchardgrid/orchardgrid
og "What is the capital of Austria?"
```

That single cask install gives you both the **OrchardGrid.app** menu-bar
app *and* the `og` command, symlinked to `/opt/homebrew/bin/og`. They
share state (sharing toggles, local server port) via macOS App Group
`group.com.orchardgrid.shared`. Run `og status` to see the live picture.

## Two back-ends, one binary

| Invocation | Back-end | Requires |
|---|---|---|
| `og "prompt"` | `LocalEngine` — `SystemLanguageModel.default` in this process | Apple Silicon + macOS 26 + Apple Intelligence enabled |
| `og --host http://mac.local:8888 "prompt"` | `RemoteEngine` — HTTP to a LAN peer running OrchardGrid.app | Peer reachable |
| `og --host https://orchardgrid.com --token sk-… "prompt"` | `RemoteEngine` — cloud relay | API key |

Both back-ends stream deltas and return OpenAI-style usage counts. Swap via
`--host` / `ORCHARDGRID_HOST` — **the rest of the interface is identical**.

## Usage

```sh
og "prompt"                              # on-device, streamed to stdout
og --chat                                # interactive REPL (on-device)
og -f file.swift "explain this"          # attach file
echo "summarize this" | og               # stdin pipe
og -o json "hello" | jq .content         # JSON output
og --temperature 0.2 --seed 42 "..."     # reproducible sampling
og --context-strategy summarize "..."    # compress old turns via model
og --context-strategy strict "..."       # fail on overflow instead of trimming
og benchmark --runs 5                    # min/median/p95/max ttft + tokens/sec
og --mcp ./calc.py "what is 41 + 1?"     # attach an MCP tool server
og mcp list ./calc.py                    # introspect an MCP server's tools

og --host https://orchardgrid.com --token sk-… "hello"   # cloud
og --host http://mac.local:8888 "hello"                   # LAN peer
```

See `og --help` for the full flag list.

## MCP (Model Context Protocol)

Attach any MCP-compliant tool server and let Apple's built-in AI call it.
Stdio transport only — pass a path to the server binary or `.py` script;
`og` spawns it, handshakes, and registers its tools natively with
`LanguageModelSession`:

```sh
og --mcp /path/to/server.py --mcp /path/to/other "how many stars on orchardgrid?"
og --mcp /path/to/server.py --mcp-timeout 30 --chat
og mcp list /path/to/server.py -o json
```

MCP requires on-device inference — combining `--mcp` with `--host` is
rejected. The handshake uses MCP protocol version `2025-06-18`.

## Configuration

| Env var | Meaning |
|---|---|
| `ORCHARDGRID_HOST` | Default remote host (omit → on-device) |
| `ORCHARDGRID_TOKEN` | Default Bearer token |
| `NO_COLOR` | Disable ANSI color output |

## Exit codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Runtime error (network, auth, unreachable) |
| 2 | Usage error (bad flags) |
| 3 | Guardrail blocked |
| 4 | Context overflow |
| 5 | Model unavailable (Apple Intelligence not enabled) |
| 6 | Rate limited |

## Build

```sh
make build        # debug build           (default cloud host → http://localhost:4399)
make release      # release build         (default cloud host → https://orchardgrid.com)
make install      # release + install     (ships production target)
make install-dev  # debug + install       (targets local dev worker)
make format       # swift-format in place
```

The default cloud host is baked in at build time via `#if DEBUG`, mirroring
the native app's `Debug.xcconfig` / `Release.xcconfig` split — so
**contributors don't need `--host http://localhost:4399`** during dev.

- Running against the local dev worker? `make install-dev` once, then
  `og login` / `og me` Just Work.
- Shipping a release? `make install` (or `brew install …`) → talks to
  production by default.

Priority order for host resolution: `--host` flag > `ORCHARDGRID_HOST` env >
saved `~/.config/orchardgrid/config.json` (management only) > build-time
default.

Requires Swift 6.2 / macOS 26+.

## Tests

Three independent tiers:

```sh
make test-unit    # Swift Testing — 64 unit tests, no network, no model
make test-int     # pytest + mock HTTP server — 43 E2E tests for RemoteEngine
make test         # both
make smoke-live   # live on-device smoke (requires Apple's built-in AI)
```

| Tier | What | Requires |
|---|---|---|
| Unit (`test-unit`) | Argument parsing, error mapping, wire coding, ANSI styling, engine factory | — |
| E2E mock (`test-int`) | Spawns `og --host <mock>` as subprocess; asserts stdout/stderr/exit code against a stubbed HTTP server | Python 3.9+, `pytest` |
| Live smoke (`smoke-live`) | Real `og` → real FoundationModels | Apple's built-in AI on this Mac |

Unit + E2E-mock run on any macOS 26 machine (no Apple's built-in AI needed).
Live smoke is release-gate only.

## Architecture

```
┌─────────────────────────────────────────┐
│              og binary                  │
│                                         │
│  main.swift                             │
│      │                                  │
│      ▼                                  │
│  EngineFactory.make(host:)              │
│      │                                  │
│      ├──host == nil─▶ LocalEngine       │
│      │                    │             │
│      │                    ▼             │
│      │            FoundationModels      │
│      │            (SystemLanguageModel) │
│      │                                  │
│      └──host != nil─▶ RemoteEngine      │
│                           │             │
│                           ▼             │
│                       HTTP + SSE        │
│                           │             │
└───────────────────────────┼─────────────┘
                            │
                            ▼
                ┌───────────────────────┐
                │ OrchardGrid.app       │
                │ or orchardgrid.com    │
                └───────────────────────┘
```

`LLMEngine` is a protocol; both engines conform to it and are
interchangeable. Inference, REPL, and output formatting are written once.
