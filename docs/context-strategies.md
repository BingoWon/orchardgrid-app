# Context strategies

Apple Intelligence's context window is **4096 tokens**, shared between the system prompt, conversation history, final user prompt, and response. When the history is too long, OrchardGrid must either trim or give up — five strategies cover the trade-offs.

Implementation lives in [`Packages/OrchardGridCore/Sources/OrchardGridCore/ContextTools.swift`](../Packages/OrchardGridCore/Sources/OrchardGridCore/ContextTools.swift), consumed identically by the CLI (`LocalEngine`) and the app (`LLMProcessor`).

## Quick guide

| Strategy | When to use | Behaviour |
|---|---|---|
| `newest-first` *(default)* | General chat | Keep the largest suffix that fits |
| `oldest-first` | Long-form edit / doc review where the opening frames the task | Keep the largest prefix that fits |
| `sliding-window` | Chat bots with a known turn budget | Cap history at `max_turns` first, then newest-first |
| `summarize` | Long multi-topic conversations | Compress the oldest half via a side model call, keep the recent half verbatim |
| `strict` | Unit tests, deterministic pipelines | Don't trim — overflow throws `context_length_exceeded` |

## Selecting a strategy

### CLI
```sh
og --chat --context-strategy summarize
og --chat --context-strategy sliding-window --context-max-turns 20
og --context-strategy strict "some prompt"
```

### HTTP extension field
```json
{
  "model": "apple-intelligence",
  "messages": [...],
  "context_strategy": "summarize",
  "context_max_turns": 20
}
```

## `newest-first` (default)

Given history + base + prompt, binary-searches the largest `k` such that `history.suffix(k)` plus `base` plus `prompt` fits the budget. O(log n) token-count calls.

Works for most use cases. The last user message is always in the transcript; earlier turns drop off as the conversation grows.

## `oldest-first`

Mirror image: keeps the largest *prefix* that fits. Useful when the opening of the conversation contains instructions or canonical context that later turns refer back to.

## `sliding-window`

Pre-caps the history at `--context-max-turns` (or the `context_max_turns` field), then runs `newest-first` on what remains. If `max_turns` isn't set, falls through to plain `newest-first`.

## `summarize`

1. Reserves ~half of the context budget for the recent verbatim tail.
2. Binary-searches the largest suffix that fits within half-budget — that's `recent`.
3. Sends the remaining older turns to `SystemLanguageModel.default` with instructions *"Summarize the following conversation in 2-3 sentences. Be concise."*
4. Replaces the older block with a single `[Summary of prior conversation]: <summary>` assistant entry.
5. If any step fails (model unavailable, empty summary, result still overflows), **silently degrades to `newest-first`** — the caller never sees an error from summarization alone.

Costs one extra in-process model call; adds seconds of latency on the first trigger. Acceptable when conversations span enough topics that a simple newest-first trim would amputate useful signal.

## `strict`

Refuses to trim. If history + base + prompt exceeds the budget, throws `ContextOverflowError` — which the CLI surfaces as exit code 4, and the HTTP layer surfaces as `{ type: "context_length_exceeded", status: 400 }`.

Use this when you control the input and want a regression test for "did the prompt get bigger than I thought?".

## Budget math

Budget computation is centralised in `OrchardGridCore`:

```swift
let budget = max(0, model.contextSize - ContextBudget.defaultOutputReserve)
// defaultOutputReserve = 512 tokens reserved for the response
```

Base + prompt must fit under `budget` before any history is added — if they don't, the processor throws immediately regardless of strategy (no amount of history-trimming saves an oversized single prompt).

## Design notes

- Every strategy is a pure function of `(base, history, prompt, budget, model)` — no shared mutable state.
- Token counting uses `SystemLanguageModel.tokenCount(for:)` on macOS 26.4+, with a chars/4 fallback when that API throws or is unavailable (pre-26.4). The fallback is deterministic, so CI without Apple Intelligence still exercises every branch.
- `summarize` is explicitly designed to *degrade silently* rather than fail — this is the right default for a best-effort feature. If you want loud failure, use `strict`.
