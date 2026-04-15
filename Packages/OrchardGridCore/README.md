# OrchardGridCore

Shared on-device AI primitives used by both the **OrchardGrid** menu-bar app (Xcode target) and the **`og`** CLI (sibling SPM package under `orchardgrid-cli/`). Everything here is pure Swift on top of [FoundationModels](https://developer.apple.com/documentation/foundationmodels) — no UI, no Clerk, no HTTP. Tests run in the package's own target, so they execute in CI without Apple development signing.

## What lives here

[`ContextTools.swift`](Sources/OrchardGridCore/ContextTools.swift) — the single source of truth for:

| Concern | API |
|---|---|
| Token counting | `tokenCount(_:model:)`, `fallbackTokens(_:)` |
| Segment extraction | `textSegments(of:)` |
| Transcript assembly | `transcriptEntries(from:)` — accepts anything conforming to `TranscriptMessage` |
| History trimming | `trim(_:base:history:prompt:budget:model:)` dispatches all five strategies; `trimBinary`, `trimWithSummary` exposed for direct use |
| Post-inference metering | `measureUsage(session:model:) -> TokenUsage?` |

Plus the shared types: `ContextStrategy`, `TokenUsage`, `ContextOverflowError`, `TranscriptMessage`, and `ContextBudget.defaultOutputReserve`.

## How to consume

### From the Xcode app

The project's `project.pbxproj` already references this package via an `XCLocalSwiftPackageReference`. Any target that needs the primitives adds `OrchardGridCore` under *Frameworks & Libraries* (or the `packageProductDependencies` list in `pbxproj`) and then:

```swift
import OrchardGridCore

let usage = await ContextTools.measureUsage(session: session, model: .default)
```

### From the `og` CLI

`orchardgrid-cli/Package.swift` declares:

```swift
dependencies: [.package(path: "../Packages/OrchardGridCore")],
targets: [
  .target(name: "ogKit", dependencies: [
    .product(name: "OrchardGridCore", package: "OrchardGridCore")
  ], ...)
]
```

## Adding a new API

1. Add the function to [`ContextTools.swift`](Sources/OrchardGridCore/ContextTools.swift) — keep it pure Swift over FoundationModels types. Don't leak app-specific types in.
2. Cover every branch in [`ContextToolsTests.swift`](Tests/OrchardGridCoreTests/ContextToolsTests.swift) — tests must run on CI runners without Apple Foundation Model, so guard model-dependent assertions so they still pass on the fallback path.
3. Call it from both `orchardgrid-cli/Sources/ogKit/LocalEngine.swift` and `orchardgrid-app/Core/Services/LLMProcessor.swift` (or wherever else it's shared). If you only have one caller, it doesn't belong here.

## Running tests

```bash
swift test --package-path Packages/OrchardGridCore   # from repo root
make test-core                                         # via Makefile
```

CI runs the same command on every push and PR via the `core` job in [`.github/workflows/test.yml`](../../.github/workflows/test.yml).

## Non-goals

- **No UI.** No `SwiftUI`, no `AppKit`, no `UIKit`.
- **No networking.** `URLSession`, Clerk, MCP — those live in the consuming targets.
- **No platform gating beyond macOS 26 / iOS 26.** FoundationModels is macOS 26+; anything requiring macOS 26.4 is guarded with `#available`.
- **No backward-compatibility shims.** This package is internal to the OrchardGrid mono-tree; callers update in lockstep.
