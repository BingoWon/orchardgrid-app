import Foundation
@preconcurrency import FoundationModels

// MARK: - Public shared types

/// Role-tagged message that can be rendered into a `Transcript.Entry`.
/// CLI and app each declare their own `ChatMessage`; both conform to
/// this via one-line extensions so callers can pass `history` directly.
public protocol TranscriptMessage: Sendable {
  var role: String { get }
  var content: String { get }
}

/// How to fit conversation history into the model's context window.
/// Shared by CLI and app so a single `trim(_:...)` call site serves both.
public enum ContextStrategy: Sendable, Equatable {
  /// Keep the largest suffix that fits — preserves recency.
  case newestFirst
  /// Keep the largest prefix that fits — preserves the conversation start.
  case oldestFirst
  /// Cap history at `maxTurns` first, then fit newest-first within budget.
  case slidingWindow(maxTurns: Int?)
  /// Compress the oldest turns into a model-generated summary, keep
  /// recent turns verbatim. Falls back to `newestFirst` on any failure.
  case summarize
  /// No trimming — throw `ContextOverflowError` if history doesn't fit.
  case strict
}

/// Thrown by `ContextTools.trim` when the `.strict` strategy can't fit
/// the history into the budget. Callers translate into their local
/// error enum (OGError in CLI, LLMError in app).
public struct ContextOverflowError: Error, Sendable {
  public init() {}
}

/// Prompt / completion / total token counts, independent of any
/// caller-specific `Usage` / `LLMResult` struct.
public struct TokenUsage: Sendable, Equatable {
  public let prompt: Int
  public let completion: Int
  public let total: Int
  public init(prompt: Int, completion: Int, total: Int) {
    self.prompt = prompt
    self.completion = completion
    self.total = total
  }
}

/// Project-wide context-budget constants.
public enum ContextBudget {
  /// Tokens reserved for the model's response when we size the input budget.
  public static let defaultOutputReserve = 512
}

// MARK: - ContextTools
//
// Pure on-device context-management primitives shared between the CLI's
// `LocalEngine` and the app's `LLMProcessor`. Static functions — the
// model is passed in explicitly so tests can run against the fallback
// path without Apple Foundation Model.

public enum ContextTools {

  // MARK: - Token counting

  /// Token count for entries. Prefers the real `tokenCount(for:)` API
  /// (SDK 26.4+); falls back to a chars/4 estimate when that API is
  /// missing or throws.
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

  /// Map any role-tagged message stream into Transcript entries. Rows
  /// whose role is neither `"user"` nor `"assistant"` are dropped — the
  /// caller keeps the system prompt in the instructions entry, not the
  /// history.
  public static func transcriptEntries(
    from messages: some Sequence<some TranscriptMessage>
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

  /// Apply the given strategy to fit history into the budget together
  /// with `base` and `prompt`. The single dispatch point used by both
  /// CLI and app — encapsulates every trim mode including summarize's
  /// silent-fallback behaviour and strict mode's overflow signalling.
  public static func trim(
    _ strategy: ContextStrategy,
    base: Transcript.Entry,
    history: [Transcript.Entry],
    prompt: Transcript.Entry,
    budget: Int,
    model: SystemLanguageModel
  ) async throws -> [Transcript.Entry] {
    switch strategy {
    case .newestFirst:
      return await trimBinary(
        base: base, history: history, prompt: prompt,
        budget: budget, fromEnd: true, model: model)
    case .oldestFirst:
      return await trimBinary(
        base: base, history: history, prompt: prompt,
        budget: budget, fromEnd: false, model: model)
    case .slidingWindow(let maxTurns):
      let windowed = Array(history.suffix(maxTurns ?? history.count))
      return await trimBinary(
        base: base, history: windowed, prompt: prompt,
        budget: budget, fromEnd: true, model: model)
    case .summarize:
      return await trimWithSummary(
        base: base, history: history, prompt: prompt,
        budget: budget, model: model)
    case .strict:
      if await tokenCount([base] + history + [prompt], model: model) <= budget {
        return history
      }
      throw ContextOverflowError()
    }
  }

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
  /// `trimBinary(fromEnd: true)`.
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

  // MARK: - Usage measurement

  /// Compute prompt / completion / total token counts from a session's
  /// transcript after inference. Returns `nil` when the SDK token-count
  /// API isn't available or the transcript is empty.
  public static func measureUsage(
    session: LanguageModelSession,
    model: SystemLanguageModel
  ) async -> TokenUsage? {
    guard #available(iOS 26.4, macOS 26.4, *) else { return nil }
    let all = Array(session.transcript)
    guard !all.isEmpty else { return nil }
    let total = (try? await model.tokenCount(for: all)) ?? 0
    let input = (try? await model.tokenCount(for: Array(all.dropLast()))) ?? 0
    return TokenUsage(
      prompt: input,
      completion: max(0, total - input),
      total: total
    )
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
      let body = textSegments(of: entry).joined()
      guard !body.isEmpty else { return nil }
      switch entry {
      case .prompt: return "User: \(body)"
      case .response: return "Assistant: \(body)"
      default: return nil
      }
    }.joined(separator: "\n")
  }
}
