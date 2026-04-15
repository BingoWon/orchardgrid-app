# CLAUDE.md — OrchardGrid Operator Guide

Operations guide for developers and AI assistants working on OrchardGrid.
Start here before reading code. When in doubt, grep the repo.

---

## Golden goal

**Turn idle Apple devices into a shared Apple Intelligence compute pool.**

Each device you install OrchardGrid on becomes both:

- A **local API server** on port 8888 (OpenAI-compatible) for LAN clients.
- A **cloud-relay worker** that accepts tasks from the OrchardGrid cloud over WebSocket and returns results.

The cloud never sees your model inputs or outputs — it only routes a task id to an available device. All inference runs on-device via FoundationModels / Vision / NaturalLanguage / Speech / SoundAnalysis / ImagePlayground.

## Non-negotiable principles

1. **All inference on-device.** The cloud is a relay, not a model host.
2. **Auth tokens fetched fresh per request.** `AuthManager.getToken()` calls `Clerk.shared.session?.getToken()` every time — no token caching, no manual refresh logic.
3. **Swift 6 strict concurrency.** All managers are `@Observable` + `@MainActor`. Non-MainActor work goes through `Task` or explicit actor isolation.
4. **Three entitlement files per platform** (release/debug × macOS/iOS). Don't collapse them. Apple Sign-In only on macOS.
5. **No backward-compatibility shims.** This is a solo-dev shipping app — delete, don't deprecate.
6. **Conventional commits drive releases.** `feat:` → minor bump, `fix:`/`perf:`/`refactor:` → patch bump. Anything else skips release.
7. **App + CLI ship as one.** The `og` CLI lives in `orchardgrid-cli/` (sibling to the Xcode project) and is bundled inside `OrchardGrid.app/Contents/Resources/og` by `make bundle-cli` (locally) or the `release.yml` "Build og CLI" + "Bundle og into the .app" steps (CI). State is shared via App Group `group.com.orchardgrid.shared` (5 entitlement files + `og.entitlements`).

---

## Architecture at a glance

```
┌──────────────────────────────────────────────────────────────┐
│  OrchardGridApp.swift  (@main, DI root)                      │
│  ├── Clerk             (auth provider)                       │
│  ├── AuthManager       (token source)                        │
│  ├── SharingManager    (cloud/local sharing orchestrator)    │
│  │     ├── WebSocketClient  (cloud relay, /device/connect)   │
│  │     └── APIServer        (local LAN, :8888)               │
│  ├── ObserverClient    (cloud event stream, /observe)        │
│  ├── DevicesManager    (GET /api/devices)                    │
│  ├── LogsManager       (GET /api/logs)                       │
│  ├── APIKeysManager    (CRUD /api/api-keys)                  │
│  ├── ChatManager       (on-device chat via FoundationModels) │
│  ├── BackgroundManager (prevent sleep / BGTask)              │
│  └── NavigationState                                          │
└──────────────────────────────────────────────────────────────┘
        │
        │   Cloud tasks arrive via WebSocket; dispatched by
        │   capability to one of six processors:
        ▼
┌──────────────────────────────────────────────────────────────┐
│  Capability Processors  (Core/Services/Processors/)          │
│  LLMProcessor   — FoundationModels, streaming, JSON Schema   │
│  ImageProcessor — ImagePlayground                            │
│  NLPProcessor   — NaturalLanguage                            │
│  VisionProcessor— Vision (OCR, classify, faces, barcodes)    │
│  SpeechProcessor— Speech (50+ languages)                     │
│  SoundProcessor — SoundAnalysis (~300 classes)               │
└──────────────────────────────────────────────────────────────┘
```

Each processor exposes a uniform shape:

```swift
static var isAvailable: Bool
static func handle(_ data: Data) async throws -> Data
```

Both WebSocketClient and APIServer dispatch to the same processors — one code path, two transports.

---

## Key files

| Purpose | Path |
|---|---|
| App entry, DI wiring | [orchardgrid-app/App/OrchardGridApp.swift](orchardgrid-app/App/OrchardGridApp.swift) |
| Auth (Clerk) | [orchardgrid-app/Features/Auth/AuthManager.swift](orchardgrid-app/Features/Auth/AuthManager.swift) |
| Cloud sharing | [orchardgrid-app/Core/Services/SharingManager.swift](orchardgrid-app/Core/Services/SharingManager.swift) |
| Cloud WebSocket (worker) | [orchardgrid-app/Core/Services/WebSocketClient.swift](orchardgrid-app/Core/Services/WebSocketClient.swift) |
| Cloud WebSocket (observer) | [orchardgrid-app/Core/Services/ObserverClient.swift](orchardgrid-app/Core/Services/ObserverClient.swift) |
| Local HTTP API (`:8888`) | [orchardgrid-app/Core/Services/APIServer.swift](orchardgrid-app/Core/Services/APIServer.swift) |
| FoundationModels chat | [orchardgrid-app/Core/Services/LLMProcessor.swift](orchardgrid-app/Core/Services/LLMProcessor.swift) |
| Runtime config | [orchardgrid-app/Core/Utilities/Config.swift](orchardgrid-app/Core/Utilities/Config.swift) |
| Logging | [orchardgrid-app/Core/Utilities/Logger.swift](orchardgrid-app/Core/Utilities/Logger.swift) |
| Build config (Debug) | [Config/Debug.xcconfig](Config/Debug.xcconfig) |
| Build config (Release) | [Config/Release.xcconfig](Config/Release.xcconfig) |
| Release pipeline | [.github/workflows/release.yml](.github/workflows/release.yml) |
| Homebrew tap | https://github.com/BingoWon/homebrew-orchardgrid |

---

## Data flow: one cloud inference task

1. External client calls `https://orchardgrid.com/v1/chat/completions` with API key.
2. Cloud picks an online device with `llm` capability and sends a task frame over that device's WebSocket.
3. `WebSocketClient` receives the frame, looks up the capability, calls `LLMProcessor.handle(_:)`.
4. `LLMProcessor` runs `SystemLanguageModel.default` on-device, streaming chunks back as `task.chunk` frames.
5. On completion, a `task.done` frame is sent; cloud forwards to the original HTTP client as SSE.

The same `LLMProcessor.handle` is invoked by `APIServer` for local `:8888` clients — with no cloud round-trip.

---

## Config & environments

All non-code config lives in `Config/*.xcconfig` and is read at runtime from `Info.plist`:

| Key | Debug | Release |
|---|---|---|
| `API_BASE_URL` | `http://localhost:4399` | `https://orchardgrid.com` |
| `CLERK_PUBLISHABLE_KEY` | `pk_test_…` | `pk_live_…` |
| Bundle ID (macOS) | `com.orchardgrid.app.dev.debug` | `com.orchardgrid.app` |

`Config.swift` fatals if either key is missing — this is intentional, misconfiguration must fail loud at launch.

WebSocket URL is derived by scheme-swapping `https→wss` / `http→ws` and appending `/ws`. The API base URL appends `/api`.

---

## Build & run

Open in Xcode:

```sh
open orchardgrid-app.xcodeproj
```

Command line:

```sh
make build         # release build for macOS
make debug         # debug build for macOS
make format        # swift-format in place
make test          # Xcode app tests (macOS + iOS) + og CLI suites
make test-xcode    # Xcode app target only
make test-cli      # og CLI: Swift unit + pytest integration
make clean         # xcodebuild clean
```

Three test tiers:

| Tier | Location | Framework | What it covers |
|---|---|---|---|
| Xcode app | [OrchardGridTests/](orchardgrid-app/OrchardGridTests/) | Swift Testing | `APIClient` networking, URL protocol stubs |
| og CLI unit | [orchardgrid-cli/Tests/ogKitTests/](orchardgrid-app/orchardgrid-cli/Tests/ogKitTests/) | Swift Testing | Argument parsing, error mapping, MCP protocol, benchmark stats, login flow, config store |
| og CLI e2e | [orchardgrid-cli/Tests/integration/](orchardgrid-app/orchardgrid-cli/Tests/integration/) | pytest + mock HTTP server | Subprocess `og` behaviour against a scripted server; MCP via self-contained Python calculator |

GitHub CI ([.github/workflows/test.yml](orchardgrid-app/.github/workflows/test.yml)) runs the full CLI suite (127 unit + 96 e2e) on every push and PR. Xcode app tests stay local-only — the app's entitlements require a development signing certificate no CI runner has. Run `make test-xcode` locally before opening a PR. `smoke-live` (live Apple Intelligence) is release-gate only.

**Swift version:** 5.0 (treat as Swift 6 concurrency — strict concurrency warnings enabled via @Observable).
**Deployment targets:** macOS 26.0, iOS 26.0 (required for FoundationModels).

---

## Release process

Fully automated on push to `main`:

1. `release.yml` parses commits since last tag. If no `feat/fix/perf/refactor`, skip release.
2. Bumps version in `project.pbxproj`, tags, creates GitHub Release.
3. macOS runner builds, signs (Developer ID), notarizes, staples, uploads DMG.
4. `update-tap` job clones `homebrew-orchardgrid`, sed-updates `version` + `sha256`, pushes.

User installs via:

```sh
brew install --cask bingowon/orchardgrid/orchardgrid
```

### Manual fallback

Never build the DMG locally for release — notarization requires the exact workflow identity + certificates. If CI breaks, fix CI.

---

## Conventions

- **Managers** are `@Observable` `@MainActor` final classes with `lastUpdated`, `isInitialLoading`, `isRefreshing`, and (currently) `lastError: String?`. This last field will migrate to a typed `APIError` enum — don't add new `lastError: String?` properties.
- **Logger** categories are strings in [Logger.swift](orchardgrid-app/Core/Utilities/Logger.swift). Add new category constants there, don't sprinkle raw strings.
- **File headers:** none. Swift imports → type definition → MARK sections. No authorship/date comments — `git blame` is the source of truth.
- **Comments:** only when the *why* is non-obvious. Never restate the code.
- **UI strings:** use `String(localized:)`. `Localizable.xcstrings` is the single translation source.

---

## Troubleshooting

| Symptom | Check |
|---|---|
| App fatals at launch with missing config key | `Config/Debug.xcconfig` / `Release.xcconfig` — both `API_BASE_URL` and `CLERK_PUBLISHABLE_KEY` must be set |
| Local API server reports port in use | Another dev build is running, or port 8888 is occupied — `APIServer.setPort()` picks alternate |
| WebSocket reconnect loop | Check `ObserverClient` logs — auth token may be stale; sign out/in resets it |
| `feat:` commit pushed but no release | Check `release.yml` run logs; commits must match regex `^(feat|fix|perf|refactor)` case-insensitively |
| Homebrew installs old version | Tap update job requires `HOMEBREW_TAP_TOKEN` secret on `orchardgrid-app` repo |

---

## PR review checklist

Before merging to `main`:

1. **Commit type is conventional.** Otherwise release will skip or bump wrong.
2. **No new `lastError: String?` properties.** Use the typed error enum once it lands.
3. **Every new WebSocket / APIServer frame has a matching processor.** The two transports must stay in sync.
4. **FoundationModels API calls are gated on `isAvailable`.** Don't crash on unsupported hardware.
5. **macOS and iOS both compile.** `make build` and `make build-ios`.
6. **No secrets in diff.** `CLERK_PUBLISHABLE_KEY` is public by design; everything else isn't.

---

## What lives outside this repo

- **Cloud backend** (API + WebSocket relay): separate Worker, not in this repo.
- **Homebrew tap**: https://github.com/BingoWon/homebrew-orchardgrid — cask only, auto-updated by release.
- **App Store Connect metadata**: managed through Xcode's organizer, not versioned here.

---

*Last reviewed: 2026-04-15*
