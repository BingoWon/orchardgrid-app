import Foundation
@preconcurrency import FoundationModels

// MARK: - LLM Result

struct LLMResult: Sendable {
  let content: String
  let promptTokens: Int
  let completionTokens: Int
  var totalTokens: Int { promptTokens + completionTokens }
}

// MARK: - Context Strategy

/// How to trim conversation history when it exceeds the token budget.
enum ContextStrategy: String, Sendable, CaseIterable {
  /// Keep the largest *suffix* that fits. The default — preserves recency.
  case newestFirst = "newest-first"
  /// Keep the largest *prefix* that fits. Preserves the conversation start.
  case oldestFirst = "oldest-first"
  /// Cap history at `maxTurns` first, then fit newest-first within budget.
  case slidingWindow = "sliding-window"
  /// Compress oldest turns into a model-generated summary; keep recent
  /// turns verbatim. Falls back to `newestFirst` on any failure.
  case summarize
  /// No trimming — throw `contextOverflow` if history doesn't fit.
  case strict
}

struct ContextConfig: Sendable {
  let strategy: ContextStrategy
  let maxTurns: Int?

  init(strategy: ContextStrategy = .newestFirst, maxTurns: Int? = nil) {
    self.strategy = strategy
    self.maxTurns = maxTurns
  }

  nonisolated static let defaults = ContextConfig()
}

// MARK: - Session Options

/// Per-request generation + context parameters forwarded from the CLI/HTTP
/// request all the way into the FoundationModels call.
struct SessionOptions: Sendable {
  let temperature: Double?
  let maxTokens: Int?
  let seed: UInt64?
  let permissive: Bool
  let contextConfig: ContextConfig

  nonisolated static let defaults = SessionOptions(
    temperature: nil, maxTokens: nil, seed: nil,
    permissive: false, contextConfig: .defaults
  )
}

// MARK: - LLM Processor

@MainActor
final class LLMProcessor {
  private let model = SystemLanguageModel.default

  var availability: SystemLanguageModel.Availability { model.availability }

  var isAvailable: Bool {
    if case .available = model.availability { return true }
    return false
  }

  var contextSize: Int { model.contextSize }

  // MARK: - Request Processing

  /// Unified handler. Pass `onChunk` for streaming; omit for a single response.
  /// The last user message is passed to `respond(to:)` directly — never
  /// duplicated inside the transcript.
  func processRequest(
    messages: [ChatMessage],
    systemPrompt: String,
    responseFormat: ResponseFormat? = nil,
    options: SessionOptions = .defaults,
    onChunk: ((String) -> Void)? = nil
  ) async throws -> LLMResult {
    guard isAvailable else { throw LLMError.modelUnavailable }
    guard let lastUser = messages.last, lastUser.role == "user" else {
      throw LLMError.invalidRequest("Last message must be from user")
    }

    let prompt = lastUser.content
    let session = try await buildSession(
      history: Array(messages.dropLast()),
      systemPrompt: systemPrompt,
      prompt: prompt,
      options: options
    )
    let genOpts = makeGenerationOptions(options)

    do {
      let content: String

      if let responseFormat, responseFormat.type == "json_schema",
        let jsonSchema = responseFormat.jsonSchema
      {
        let schema = try SchemaConverter().convert(jsonSchema)
        if let onChunk {
          content = try await streamJSON(
            session: session, prompt: prompt, schema: schema, options: genOpts, onChunk: onChunk)
        } else {
          content = try await withRetry {
            try await session.respond(to: prompt, schema: schema, options: genOpts).content
              .jsonString
          }
        }
      } else if let onChunk {
        content = try await streamText(
          session: session, prompt: prompt, options: genOpts, onChunk: onChunk)
      } else {
        content = try await withRetry {
          try await session.respond(to: prompt, options: genOpts).content
        }
      }

      return await measureUsage(content: content, session: session)
    } catch {
      throw LLMError.classify(error)
    }
  }

  // MARK: - Instruction Token Count (shared static helper)

  /// Token count for instructions + optional tool schemas. Static because it
  /// needs no per-instance state — `SystemLanguageModel.default` is shared.
  static func measureInstructions(_ text: String, tools: [any Tool] = []) async -> Int {
    guard #available(iOS 26.4, macOS 26.4, *) else { return 0 }
    let model = SystemLanguageModel.default
    let instrTokens = (try? await model.tokenCount(for: Instructions(text))) ?? 0
    guard !tools.isEmpty else { return instrTokens }
    let toolTokens = (try? await model.tokenCount(for: tools)) ?? 0
    return instrTokens + toolTokens
  }

  // MARK: - Generation Options

  private func makeGenerationOptions(_ options: SessionOptions) -> GenerationOptions {
    let sampling: GenerationOptions.SamplingMode? = options.seed.map {
      .random(top: 50, seed: $0)
    }
    return GenerationOptions(
      sampling: sampling,
      temperature: options.temperature,
      maximumResponseTokens: options.maxTokens
    )
  }

  // MARK: - Session Builder with Token Budget

  /// Builds a `LanguageModelSession` whose transcript holds instructions +
  /// the trimmed history. The final user prompt is *not* in the transcript —
  /// it is passed to `respond(to:)`.
  private func buildSession(
    history: [ChatMessage],
    systemPrompt: String,
    prompt: String,
    options: SessionOptions
  ) async throws -> LanguageModelSession {
    let instrEntry = Transcript.Entry.instructions(
      Transcript.Instructions(
        segments: [.text(.init(content: systemPrompt))],
        toolDefinitions: []
      )
    )
    let promptEntry = Transcript.Entry.prompt(
      Transcript.Prompt(segments: [.text(.init(content: prompt))])
    )

    let budget = max(0, contextSize - Config.llmOutputReserve)
    guard await tokenCount([instrEntry, promptEntry]) <= budget else {
      throw LLMError.contextOverflow
    }

    let historyEntries = Self.transcriptEntries(for: history)
    let trimmed = try await trimHistory(
      base: instrEntry, history: historyEntries, prompt: promptEntry,
      budget: budget, config: options.contextConfig)

    let sessionModel =
      options.permissive
      ? SystemLanguageModel(guardrails: .permissiveContentTransformations)
      : model

    return LanguageModelSession(
      model: sessionModel,
      transcript: Transcript(entries: [instrEntry] + trimmed)
    )
  }

  // MARK: - Token Counting

  private func tokenCount(_ entries: [Transcript.Entry]) async -> Int {
    guard !entries.isEmpty else { return 0 }
    if #available(iOS 26.4, macOS 26.4, *) {
      return (try? await model.tokenCount(for: entries)) ?? fallbackCount(entries)
    }
    return fallbackCount(entries)
  }

  /// chars/4 approximation used when the real API is unavailable (pre 26.4)
  /// or fails. Walks all text segments the entry exposes.
  private func fallbackCount(_ entries: [Transcript.Entry]) -> Int {
    entries.reduce(0) { $0 + Self.textSegments(of: $1).reduce(0) { $0 + max(1, $1.count / 4) } }
  }

  private static func textSegments(of entry: Transcript.Entry) -> [String] {
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

  // MARK: - History Trimming

  /// Dispatches to the configured strategy. Strict mode throws if the full
  /// history doesn't fit; other modes trim until it does.
  private func trimHistory(
    base: Transcript.Entry,
    history: [Transcript.Entry],
    prompt: Transcript.Entry,
    budget: Int,
    config: ContextConfig
  ) async throws -> [Transcript.Entry] {
    switch config.strategy {
    case .newestFirst:
      return await trimBinary(
        base: base, history: history, prompt: prompt, budget: budget, fromEnd: true)
    case .oldestFirst:
      return await trimBinary(
        base: base, history: history, prompt: prompt, budget: budget, fromEnd: false)
    case .slidingWindow:
      let windowed = Array(history.suffix(config.maxTurns ?? history.count))
      return await trimBinary(
        base: base, history: windowed, prompt: prompt, budget: budget, fromEnd: true)
    case .summarize:
      return await trimWithSummary(
        base: base, history: history, prompt: prompt, budget: budget)
    case .strict:
      let all = [base] + history + [prompt]
      if await tokenCount(all) <= budget { return history }
      throw LLMError.contextOverflow
    }
  }

  /// Compress old history into a short model-generated summary, keep recent
  /// turns verbatim. On any failure (model unavailable, empty text, result
  /// still overflows) degrade silently to `newest-first`.
  private func trimWithSummary(
    base: Transcript.Entry,
    history: [Transcript.Entry],
    prompt: Transcript.Entry,
    budget: Int
  ) async -> [Transcript.Entry] {
    let fallback: () async -> [Transcript.Entry] = {
      await self.trimBinary(
        base: base, history: history, prompt: prompt, budget: budget, fromEnd: true)
    }
    guard history.count > 2, isAvailable else { return await fallback() }

    let halfBudget = budget / 2
    var lo = 0
    var hi = history.count
    while lo < hi {
      let mid = (lo + hi + 1) / 2
      if await tokenCount([base] + Array(history.suffix(mid)) + [prompt]) <= halfBudget {
        lo = mid
      } else {
        hi = mid - 1
      }
    }
    let recent = Array(history.suffix(lo))
    let old = Array(history.dropLast(lo))
    guard !old.isEmpty else { return recent }

    let oldText = Self.renderForSummary(old)
    guard !oldText.isEmpty, let summary = await generateSummary(oldText) else {
      return await fallback()
    }

    let summaryEntry = Transcript.Entry.response(
      Transcript.Response(
        assetIDs: [],
        segments: [.text(.init(content: "[Summary of prior conversation]: \(summary)"))]
      )
    )
    let assembled = [summaryEntry] + recent
    if await tokenCount([base] + assembled + [prompt]) <= budget { return assembled }
    return await fallback()
  }

  private func generateSummary(_ text: String) async -> String? {
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
      default: return nil
      }
    }.joined(separator: "\n")
  }

  /// Binary-search the largest `k` for which `history.suffix(k)` (or prefix,
  /// if `fromEnd == false`) fits inside the budget with `base` and `prompt`.
  private func trimBinary(
    base: Transcript.Entry,
    history: [Transcript.Entry],
    prompt: Transcript.Entry,
    budget: Int,
    fromEnd: Bool
  ) async -> [Transcript.Entry] {
    var lo = 0
    var hi = history.count
    while lo < hi {
      let mid = (lo + hi + 1) / 2
      let slice = fromEnd ? history.suffix(mid) : history.prefix(mid)
      if await tokenCount([base] + Array(slice) + [prompt]) <= budget {
        lo = mid
      } else {
        hi = mid - 1
      }
    }
    return fromEnd ? Array(history.suffix(lo)) : Array(history.prefix(lo))
  }

  // MARK: - Token Measurement (post-response)

  /// Compute prompt/completion split from the transcript after inference.
  /// Uses a single overload (`[Transcript.Entry]`) so the two counts stay on
  /// the same scale — prompt + completion always equals total.
  private func measureUsage(content: String, session: LanguageModelSession) async -> LLMResult {
    guard #available(iOS 26.4, macOS 26.4, *) else {
      return LLMResult(content: content, promptTokens: 0, completionTokens: 0)
    }
    let all = Array(session.transcript)
    let total = (try? await model.tokenCount(for: all)) ?? 0
    let input = (try? await model.tokenCount(for: Array(all.dropLast()))) ?? 0
    return LLMResult(
      content: content,
      promptTokens: input,
      completionTokens: max(0, total - input)
    )
  }

  // MARK: - Retry (exponential back-off)

  private func withRetry<T>(
    maxAttempts: Int = 3,
    _ operation: () async throws -> T
  ) async throws -> T {
    var attempt = 0
    while true {
      do {
        return try await operation()
      } catch {
        let classified = LLMError.classify(error)
        attempt += 1
        guard classified.isRetryable, attempt < maxAttempts else { throw classified }
        try? await Task.sleep(for: .seconds(Double(1 << (attempt - 1))))  // 1 s, 2 s, 4 s
      }
    }
  }

  // MARK: - Stream Helpers

  private func streamText(
    session: LanguageModelSession,
    prompt: String,
    options: GenerationOptions,
    onChunk: (String) -> Void
  ) async throws -> String {
    var full = ""
    var prev = ""
    for try await snapshot in session.streamResponse(to: prompt, options: options) {
      full = snapshot.content
      let delta = String(full.dropFirst(prev.count))
      if !delta.isEmpty { onChunk(delta) }
      prev = full
    }
    return full
  }

  private func streamJSON(
    session: LanguageModelSession,
    prompt: String,
    schema: GenerationSchema,
    options: GenerationOptions,
    onChunk: (String) -> Void
  ) async throws -> String {
    var full = ""
    var prev = ""
    for try await snapshot in session.streamResponse(to: prompt, schema: schema, options: options) {
      full = snapshot.content.jsonString
      let delta = String(full.dropFirst(prev.count))
      if !delta.isEmpty { onChunk(delta) }
      prev = full
    }
    return full
  }

  // MARK: - Transcript Entry Builder

  static func transcriptEntries(for messages: [ChatMessage]) -> [Transcript.Entry] {
    messages.compactMap { message in
      switch message.role {
      case "user":
        .prompt(Transcript.Prompt(segments: [.text(.init(content: message.content))]))
      case "assistant":
        .response(
          Transcript.Response(assetIDs: [], segments: [.text(.init(content: message.content))]))
      default:
        nil
      }
    }
  }
}
