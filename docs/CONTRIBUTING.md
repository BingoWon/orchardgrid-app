# Contributing

Bug reports, feature requests, and pull requests are all welcome.

## Before you start

- This is an Apple-platform codebase: **Xcode 26+**, **macOS 26+**, **Apple Silicon**. No Intel Macs, no Linux CI for the Swift side.
- Cloud-side changes live in [BingoWon/orchardgrid](https://github.com/BingoWon/orchardgrid) — that's a different repo with its own issue tracker.
- Read [ARCHITECTURE.md](ARCHITECTURE.md) first if you're touching more than one target.

## Development loop

```sh
make debug               # fast compile cycle
make format              # swift-format in-place
make test                # every test in the repo (Core + Xcode + og CLI)
make test-core           # just the OrchardGridCore package (~1s)
make test-cli            # just the CLI (Swift unit + pytest e2e)
make test-xcode-macos    # just the Xcode app target
make bundle              # release build + bundle og into OrchardGrid.app
```

See [TESTING.md](TESTING.md) for the four-tier test pyramid and what runs on CI vs what's release-gated.

## Commit style

Every commit on `main` goes through the Conventional Commits parser in `release.yml` to decide whether to cut a release:

| Prefix | Effect |
|---|---|
| `feat:` | minor version bump |
| `fix:` / `perf:` / `refactor:` | patch version bump |
| `chore:` / `docs:` / `test:` / `ci:` / `build:` | **no release** |

Commits that don't match that regex never trigger the release pipeline — use them freely for docs / chore / test-only changes.

**Body**: explain the *why*, not the *what*. The diff shows what changed; the message should explain why. Link any issue by number.

**Trailers**: when an AI agent helped, credit it with a `Co-Authored-By:` trailer. Example:

```
Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
```

Humans and agents are reviewed on the same bar: clean code, passing tests, honesty about limits.

## Pull request checklist

Before requesting review:

1. `make test` is green locally (all four tiers).
2. `make format` has run — no unstaged formatter changes.
3. Commit message uses Conventional Commits and explains the *why*.
4. No new `lastError: String?` on managers — use the typed `APIError` enum.
5. Every new WebSocket / APIServer frame has a matching processor. The two transports must stay in sync.
6. FoundationModels API calls are gated on `isAvailable`. Don't crash on unsupported hardware.
7. macOS and iOS both compile: `make build-macos` + `make build-ios`.
8. No secrets in the diff. `CLERK_PUBLISHABLE_KEY` is public by design; everything else is not.

## Where to put new code

| Concern | Home |
|---|---|
| Pure Swift over FoundationModels (context trimming, token counting, protocol framing) | `Packages/OrchardGridCore/` |
| CLI flags, subprocess handling, HTTP client for `RemoteEngine` | `orchardgrid-cli/Sources/ogKit/` |
| SwiftUI views, managers, Clerk, Network framework | `orchardgrid-app/` |
| Shared types on the `/v1/*` wire | `orchardgrid-app/Core/Models/SharedTypes.swift` |

If something *could* be tested without Apple Foundation Model or code signing, it belongs in OrchardGridCore. That's the rule for every refactor.

## Tests & quality gates

Every PR runs [test.yml](../.github/workflows/test.yml) on GitHub Actions:

- **Core job**: `swift test --package-path Packages/OrchardGridCore`
- **CLI job**: `make -C orchardgrid-cli test` (Swift unit + pytest e2e)

Xcode app tests run locally only (entitlements reject unsigned builds). Before merging, run `make test-xcode-macos` on your Mac with a dev cert configured.

## Docs

- **User-facing docs** (CLI reference, context strategies, MCP, OpenAI compatibility) live on [orchardgrid.com/docs](https://orchardgrid.com/docs), sourced from `src/docs/*.md` in the [cloud repo](https://github.com/BingoWon/orchardgrid).
- **Contributor docs** (this file + [ARCHITECTURE.md](ARCHITECTURE.md) + [RELEASING.md](RELEASING.md) + [TESTING.md](TESTING.md)) live here.
- **README** markets the product to end users. Keep it terse and link into the web docs rather than duplicating content.

## Releasing

Don't — the release pipeline runs automatically on every Conventional-Commits match against `main`. See [RELEASING.md](RELEASING.md) for the sequence and how to intervene when it breaks.
