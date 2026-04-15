import Foundation
@preconcurrency import FoundationModels

// MARK: - ContextTools
//
// Pure on-device context-management primitives shared between the CLI's
// `LocalEngine` and the app's `LLMProcessor`. Previously duplicated
// verbatim across the two codebases; consolidated here.
//
// All functions are static — there's no per-instance state. `model` is
// passed in explicitly so callers (who typically hold their own
// `SystemLanguageModel.default`) can route real token-counting API
// calls through it, while tests can skip that path by relying on the
// chars/4 fallback when the SDK's tokenCount throws or is unavailable.

public enum ContextTools {

  // MARK: - Token counting

  /// Token count for entries. Prefers the real `SystemLanguageModel`
  /// `tokenCount(for:)` API (SDK 26.4+); falls back to a chars/4
  /// estimate when that API is missing or throws.
  public static func tokenCount(
    _ entries: [Transcript.Entry],
    model: SystemLanguageModel
  ) async -> Int {
    guard !entries.isEmpty else { return 0 }
    if #available(iOS 26.4, macOS 26.4, *) {
      return (try? await model.tokenCount(for: entries)) ?? fallbackTokens(entries)
    }
    return fallbackTokens(entries)
  }

  /// Deterministic chars/4 token estimate. Each segment contributes at
  /// least 1 so empty-but-present segments are never free.
  public static func fallbackTokens(_ entries: [Transcript.Entry]) -> Int {
    entries.reduce(0) { acc, entry in
      acc + textSegments(of: entry).reduce(0) { $0 + max(1, $1.count / 4) }
    }
  }

  /// Extract the text payload from each segment the entry exposes.
  /// Tool-call entries have no plain text, returned as empty.
  public static func textSegments(of entry: Transcript.Entry) -> [String] {
    let segments: [Transcript.Segment]
    switch entry {
    case .instructions(let i): segments = i.segments
    case .prompt(let p): segments = p.segments
    case .response(let r): segments = r.segments
    case .toolOutput(let o): segments = o.segments
    case .toolCalls: return []
    @unknown default: return []
    }
    return segments.compactMap {
      if case .text(let t) = $0 { return t.content } else { return nil }
    }
  }

  // MARK: - Transcript assembly

  /// Map `[(role, content)]` to Transcript entries. Rows whose role
  /// is neither `"user"` nor `"assistant"` are dropped — the caller
  /// keeps system prompts in the instructions entry, not the history.
  public static func transcriptEntries(
    from messages: [(role: String, content: String)]
  ) -> [Transcript.Entry] {
    messages.compactMap { m in
      switch m.role {
      case "user":
        .prompt(Transcript.Prompt(segments: [.text(.init(content: m.content))]))
      case "assistant":
        .response(
          Transcript.Response(
            assetIDs: [], segments: [.text(.init(content: m.content))]))
      default:
        nil
      }
    }
  }

  // MARK: - Trimming

  /// Binary-search the largest `k` for which `history.suffix(k)` (or
  /// prefix, when `fromEnd == false`) fits inside `budget` together
  /// with `base` and `prompt`. O(log n) `tokenCount` calls.
  public static func trimBinary(
    base: Transcript.Entry,
    history: [Transcript.Entry],
    prompt: Transcript.Entry,
    budget: Int,
    fromEnd: Bool,
    model: SystemLanguageModel
  ) async -> [Transcript.Entry] {
    var lo = 0
    var hi = history.count
    while lo < hi {
      let mid = (lo + hi + 1) / 2
      let slice = fromEnd ? history.suffix(mid) : history.prefix(mid)
      if await tokenCount([base] + Array(slice) + [prompt], model: model) <= budget {
        lo = mid
      } else {
        hi = mid - 1
      }
    }
    return fromEnd ? Array(history.suffix(lo)) : Array(history.prefix(lo))
  }

  /// Compress the oldest turns into a short model-generated summary,
  /// keep recent turns verbatim. On any failure (model unavailable,
  /// empty text, summary still overflows) degrade silently to
  /// `trimBinary(fromEnd: true)` so the caller never sees an error.
  public static func trimWithSummary(
    base: Transcript.Entry,
    history: [Transcript.Entry],
    prompt: Transcript.Entry,
    budget: Int,
    model: SystemLanguageModel
  ) async -> [Transcript.Entry] {
    let fallback: () async -> [Transcript.Entry] = {
      await trimBinary(
        base: base, history: history, prompt: prompt,
        budget: budget, fromEnd: true, model: model)
    }
    guard history.count > 2, case .available = model.availability else {
      return await fallback()
    }

    // Reserve roughly half the budget for the recent verbatim tail.
    let halfBudget = budget / 2
    var lo = 0
    var hi = history.count
    while lo < hi {
      let mid = (lo + hi + 1) / 2
      if await tokenCount(
        [base] + Array(history.suffix(mid)) + [prompt], model: model
      ) <= halfBudget {
        lo = mid
      } else {
        hi = mid - 1
      }
    }
    let recent = Array(history.suffix(lo))
    let old = Array(history.dropLast(lo))
    guard !old.isEmpty else { return recent }

    let oldText = renderForSummary(old)
    guard !oldText.isEmpty,
      let summary = await generateSummary(oldText, model: model)
    else {
      return await fallback()
    }

    let summaryEntry = Transcript.Entry.response(
      Transcript.Response(
        assetIDs: [],
        segments: [.text(.init(content: "[Summary of prior conversation]: \(summary)"))]
      )
    )
    let assembled = [summaryEntry] + recent
    if await tokenCount([base] + assembled + [prompt], model: model) <= budget {
      return assembled
    }
    return await fallback()
  }

  // MARK: - Summary helpers (private)

  private static func generateSummary(
    _ text: String,
    model: SystemLanguageModel
  ) async -> String? {
    let session = LanguageModelSession(
      model: model,
      instructions: "Summarize the following conversation in 2-3 sentences. Be concise."
    )
    do {
      let response = try await session.respond(to: text)
      let trimmed = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
      return trimmed.isEmpty ? nil : trimmed
    } catch {
      return nil
    }
  }

  private static func renderForSummary(_ entries: [Transcript.Entry]) -> String {
    entries.compactMap { entry -> String? in
      switch entry {
      case .prompt(let p):
        let text = p.segments.compactMap { seg -> String? in
          if case .text(let t) = seg { return t.content } else { return nil }
        }.joined()
        return text.isEmpty ? nil : "User: \(text)"
      case .response(let r):
        let text = r.segments.compactMap { seg -> String? in
          if case .text(let t) = seg { return t.content } else { return nil }
        }.joined()
        return text.isEmpty ? nil : "Assistant: \(text)"
      default:
        return nil
      }
    }.joined(separator: "\n")
  }
}
