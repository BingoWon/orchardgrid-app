# Stability policy

This document sets expectations about what OrchardGrid guarantees across versions and what it does not.

## Versioning

OrchardGrid follows **semver** for its public surfaces:

- **MAJOR** — removing or incompatibly changing a public surface below.
- **MINOR** — new capabilities, new endpoints, new optional request fields.
- **PATCH** — bug fixes and performance improvements.

The version in `Config/Release.xcconfig` and the Homebrew cask is the source of truth.

## What is stable

- **Local HTTP API on `:8888`** — endpoint paths, request shapes, and response shapes are stable within a major version. OpenAI-compatible paths (`/v1/chat/completions`, `/v1/images/generations`, etc.) follow the OpenAI schema unless explicitly documented otherwise.
- **Cloud-facing WebSocket frame schema** — the task/chunk/done message shape between device and cloud is stable within a major version.
- **Entitlements set** — adding entitlements requires a minor bump; removing one is a major bump.
- **Config keys** (`API_BASE_URL`, `CLERK_PUBLISHABLE_KEY`) — renaming is a major bump.
- **Semantic behaviour of capability toggles** — enabling `llm` will always route LLM tasks; we won't silently redefine what a capability means.

## What is NOT stable

- **Model outputs.** Apple controls FoundationModels / Vision / Speech / etc. The same input can produce different outputs across macOS updates. This is not a bug in OrchardGrid.
- **Performance.** Tokens/sec, latency, and throughput depend on device, thermal state, battery, and Apple's models. No numerical guarantees.
- **Internal module boundaries.** File layout under `orchardgrid-app/` may change at any time. If you're importing OrchardGrid source directly, you're off-script.
- **Log formats and log categories.** Logs are for humans, not parsing.
- **Debug builds.** Debug config points to localhost infrastructure and test Clerk keys — never relied upon externally.

## Breaking-change protocol

When a breaking change is unavoidable:

1. The change ships in a **major** release.
2. Release notes call it out under a **Breaking changes** heading.
3. If feasible, a migration note is added to [CLAUDE.md](CLAUDE.md) for one major cycle.

No silent semantic changes. If behaviour changes without a version bump that reflects it, that's a bug — file it.

## Deprecation

We don't do long deprecation windows. This is a solo-dev shipping app — a deprecated surface is a liability. When something goes, it goes in the next major with a line in the release notes.

---

*Last reviewed: 2026-04-14*
