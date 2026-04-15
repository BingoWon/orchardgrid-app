# Testing

Six test tiers, three tool stacks. Each tier covers what the others can't — together they give us coverage from pure logic all the way out to real Apple Foundation Model. The matrix below tells you where to put a new test.

## Tiers

| Tier | Location | Framework | What it covers | Runs on CI? |
|---|---|---|---|:---:|
| **OrchardGridCore unit** | `Packages/OrchardGridCore/Tests/` | Swift Testing | Context trimming, token counting, transcript assembly, summary fallback, `ModelIssue` classification, `Retry` backoff, MCP wire protocol | ✅ |
| **og CLI unit** | `orchardgrid-cli/Tests/ogKitTests/` | Swift Testing | Argument parsing, error mapping, benchmark stats, login flow URL building, loopback server binding, config store, subcommand dispatch, MCP argument validation | ✅ |
| **og CLI pytest e2e** | `orchardgrid-cli/Tests/integration/` | pytest + hand-rolled mock HTTP server | Subprocess `og` behaviour against a scripted server; login round-trip; MCP against a self-contained Python calculator | ✅ |
| **Worker vitest** | `orchardgrid/worker/**/*.test.ts` (separate repo) | vitest + mocked D1 | `resolveToken` branches, `requireManagementScope`, crypto helpers, device-row parsing | ✅ (on `BingoWon/orchardgrid`) |
| **Xcode app** | `OrchardGridTests/` | Swift Testing | `APIClient` networking, URL protocol stubs | local only — entitlements reject unsigned builds |
| **Live smoke** | `scripts/smoke-live/` + `orchardgrid-cli/scripts/smoke-live.sh` | bash + python3 | Real FoundationModels + ImagePlayground + Vision + Speech + NaturalLanguage + SoundAnalysis through the running app's `:8888` | local / release-gate only |

## One entrypoint

```sh
make test           # every tier that can run locally
```

Specifically:

```sh
make test-core      # OrchardGridCore (fast, ~1s)
make test-cli       # og CLI unit + pytest e2e (~2min; needs a `release` binary)
make test-xcode     # Xcode app (macOS + iOS, requires dev cert)
```

Release-gate smoke, run before `git push main` on risky changes:

```sh
make smoke-live-capabilities                  # six capabilities via :8888
make -C orchardgrid-cli smoke-live            # og against real FoundationModels
```

Worker tests run in the cloud repo:

```sh
cd ../orchardgrid && pnpm test
```

## Where new tests go

Ask in order:

1. **Can this be tested without Apple Foundation Model, without signing, without a running app?**
   → `Packages/OrchardGridCore/Tests/` (unit, runs on Linux-grade CI)
2. **Does it test a CLI argument / subprocess / flag / config file?**
   → `orchardgrid-cli/Tests/ogKitTests/` (Swift unit) or `Tests/integration/` (pytest, if it needs a running `og` binary + HTTP)
3. **Does it test the HTTP API (`/v1/*` wire behaviour)?**
   → Live smoke (`scripts/smoke-live/capabilities.py`). There is no mock-able substitute for Apple's six frameworks.
4. **Does it test the worker (auth, routes, D1)?**
   → `BingoWon/orchardgrid` repo, vitest.
5. **Does it test the Xcode app target (SwiftUI, Clerk, Network framework)?**
   → `OrchardGridTests/` — last resort, CI can't run it.

## CI gate

[.github/workflows/test.yml](../.github/workflows/test.yml) runs on every push + PR. Two parallel jobs on `macos-26` with `maxim-lobanov/setup-xcode@latest-stable`:

- **OrchardGridCore (shared primitives)** — `swift test --package-path Packages/OrchardGridCore`
- **og CLI (Swift unit + pytest e2e)** — `make -C orchardgrid-cli test`

The Xcode app target can't run here — its entitlements (App Group, hardened runtime, Clerk keychain) require a real Apple development certificate. Contributors run `make test-xcode` locally before opening a PR; that gate is honor-system.

Live smoke is never in CI. It requires real Apple Foundation Model on the runner; no GitHub runner has that.

## Pyramid philosophy

```
                       Live smoke (hand-run before release)
                    ┌──────────────────────────────────────┐
                    │  Real model · real 6 capabilities    │
                    └──────────────────────────────────────┘
                 Xcode app (local dev cert)
              ┌───────────────────────────────────┐
              │  APIClient, URL protocol stubs    │
              └───────────────────────────────────┘
             og CLI pytest e2e (CI)
         ┌─────────────────────────────────┐
         │  Subprocess og · mock HTTP      │
         └─────────────────────────────────┘
         og CLI unit (CI)            Worker vitest (CI)
     ┌──────────────────────┐    ┌──────────────────────┐
     │  Arg parse, MCP arg, │    │  resolveToken, auth, │
     │  benchmark, login    │    │  crypto, types       │
     └──────────────────────┘    └──────────────────────┘
                OrchardGridCore unit (CI, fastest)
     ┌─────────────────────────────────────────────────┐
     │  ContextTools, ModelIssue, Retry, MCPProtocol   │
     └─────────────────────────────────────────────────┘
```

Move tests **down** the pyramid whenever possible. If a test needs the full Xcode app target but the logic could be pulled into `OrchardGridCore`, the refactor pays for itself the first time CI catches a regression.
