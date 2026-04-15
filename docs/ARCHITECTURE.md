# Architecture

High-level map of how the pieces fit together. Start here before reading code.

## Three artefacts, one product

| Artefact | Lives in | Ships as |
|---|---|---|
| **OrchardGrid.app** (macOS menu-bar + iOS / iPadOS) | `orchardgrid-app/` Xcode target | App Store + Homebrew cask |
| **`og` CLI** | `orchardgrid-cli/` SPM package | bundled inside `OrchardGrid.app/Contents/Resources/og`; `brew install --cask` symlinks onto PATH |
| **OrchardGridCore** shared primitives | `Packages/OrchardGridCore/` SPM package | local dependency of both the app target and the CLI package |

Cloud-side relay (Cloudflare Workers + React dashboard + D1) lives in the separate [BingoWon/orchardgrid](https://github.com/BingoWon/orchardgrid) repo. The two talk over HTTPS + WebSocket.

## Module boundaries

```text
┌──────────────────────────────────────────────────────────────┐
│ OrchardGrid.app (Xcode target, macOS + iOS)                  │
│   @main OrchardGridApp — DI root, SwiftUI lifecycle          │
│   Features/      Auth · Chat · Navigation · Sharing · ...    │
│   Core/Services/ APIServer · WebSocketClient · LLMProcessor  │
│                  ImageProcessor · NLPProcessor · ...         │
│   Core/Models/   SharedTypes — wire DTOs for /v1/*            │
│   Core/Errors/   APIError · LLMError                          │
└──────────────────────────────────────────────────────────────┘
                         │   imports
                         ▼
┌──────────────────────────────────────────────────────────────┐
│ OrchardGridCore (SPM, pure Swift over FoundationModels)      │
│   ContextTools       tokenCount · trimBinary · trimWithSummary│
│                      transcriptEntries · measureUsage         │
│   ContextStrategy    typed enum with associated values        │
│   ContextBudget      defaultOutputReserve = 512               │
│   TranscriptMessage  protocol — CLI + app ChatMessage conform │
│   TokenUsage         prompt / completion / total              │
│   ModelIssue         abstract GenerationError classifier      │
│   Retry.withRetry    exponential-backoff primitive            │
│   MCPProtocol        JSON-RPC 2.0 framing + parsing           │
│   MCPLineReader      poll(2)-gated buffered stdio reader      │
└──────────────────────────────────────────────────────────────┘
                         ▲
                         │   imports
┌──────────────────────────────────────────────────────────────┐
│ ogKit (SPM library, inside orchardgrid-cli/)                 │
│   LLMEngine + LocalEngine + RemoteEngine                     │
│   MCPClient — MCPConnection + MCPManager + MCPTool           │
│   Arguments · Inference · Benchmark · LoginFlow · CloudAPI   │
│   AuthCommands · MgmtCommands · StatusCommand · MCPCommands  │
└──────────────────────────────────────────────────────────────┘
                         ▲
                         │   imports
┌──────────────────────────────────────────────────────────────┐
│ og (executable target)                                       │
│   main.swift — parse, dispatch, printUsage                   │
└──────────────────────────────────────────────────────────────┘
```

## Data flow: one cloud inference task

1. External client calls `https://orchardgrid.com/v1/chat/completions` with an API key.
2. Worker picks an online device with `llm` capability and pushes a task frame over that device's WebSocket.
3. `WebSocketClient` (in the app) receives the frame, looks up the capability, calls `LLMProcessor.handle(_:)`.
4. `LLMProcessor` runs `SystemLanguageModel.default` on-device, streaming chunks back as `task.chunk` frames.
5. On completion, a `task.done` frame is sent; the worker forwards to the original HTTP client as SSE.

Same `LLMProcessor.handle` is invoked by `APIServer` for local `:8888` clients — with no cloud round-trip.

## Six capability processors

Each has the same shape so cloud WebSocket and local HTTP dispatch stay identical:

```swift
static var isAvailable: Bool
static func handle(_ data: Data) async throws -> Data
```

| Processor | Apple framework | Wire path |
|---|---|---|
| `LLMProcessor` | FoundationModels | `/v1/chat/completions` |
| `ImageProcessor` | ImagePlayground | `/v1/images/generations` |
| `NLPProcessor` | NaturalLanguage | `/v1/nlp/analyze` |
| `VisionProcessor` | Vision | `/v1/vision/analyze` |
| `SpeechProcessor` | Speech | `/v1/audio/transcriptions` |
| `SoundProcessor` | SoundAnalysis | `/v1/audio/classify` |

## Why the three-way split

- **OrchardGridCore** stays pure (Foundation + FoundationModels only) so its tests run on CI runners without Apple development certificates or Apple Intelligence.
- **ogKit** adds HTTP / subprocess / config-file concerns that only the CLI needs. No UI.
- **The Xcode target** pulls in Clerk, GoogleSignIn, SwiftUI, Network framework, App Group entitlements — everything that requires code signing.

When you're adding a primitive that could be tested without a running app or Apple Intelligence, it belongs in OrchardGridCore. When it requires spawning subprocesses or speaking HTTP, it belongs in ogKit. When it renders UI or touches Clerk, it's an app-target concern.

## Conventions

- **Managers** are `@Observable @MainActor final class`. They expose `lastUpdated`, `isInitialLoading`, `isRefreshing`, and a typed `APIError?`.
- **Logger** categories are string constants in `Core/Utilities/Logger.swift`. Don't sprinkle raw strings.
- **No file headers** — Swift imports → type definition → MARK sections. No authorship/date comments; `git blame` is the source of truth.
- **Comments** only when the *why* is non-obvious. Never restate the code.
- **UI strings** use `String(localized:)`. `Localizable.xcstrings` is the single translation source.
- **Three entitlement files per platform** (release / debug / DMG × macOS + iOS) — don't collapse them.
- **No backwards-compatibility shims.** This is a solo-dev shipping app; delete, don't deprecate.

## Config & environments

All non-code config lives in `Config/*.xcconfig` and is read at runtime from `Info.plist`:

| Key | Debug | Release |
|---|---|---|
| `API_BASE_URL` | `http://localhost:4399` | `https://orchardgrid.com` |
| `CLERK_PUBLISHABLE_KEY` | `pk_test_…` | `pk_live_…` |
| Bundle ID (macOS) | `com.orchardgrid.app.dev.debug` | `com.orchardgrid.app` |

`Config.swift` fatals at launch if either key is missing — intentional; misconfiguration must fail loud.

## What lives outside this repo

- **Cloud Worker + dashboard**: [BingoWon/orchardgrid](https://github.com/BingoWon/orchardgrid) — Cloudflare Workers + React.
- **Homebrew tap**: [BingoWon/homebrew-orchardgrid](https://github.com/BingoWon/homebrew-orchardgrid) — cask only; auto-updated by `release.yml`.
- **App Store Connect metadata**: managed through Xcode's organiser, not versioned here.
