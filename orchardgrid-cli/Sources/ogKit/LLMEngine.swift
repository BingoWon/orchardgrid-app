import Foundation
@preconcurrency import FoundationModels

// MARK: - Engine Protocol

/// A unified interface over on-device (FoundationModels) and remote (HTTP)
/// inference. Both back-ends stream content chunks and return usage counts.
public protocol LLMEngine: Sendable {
  /// Describe the engine's source + availability. Used by `og --model-info`.
  func health() async throws -> EngineHealth

  /// Run a streaming chat completion. `onDelta` fires for each content chunk.
  func chat(
    messages: [ChatMessage],
    options: ChatOptions,
    onDelta: @Sendable (String) -> Void
  ) async throws -> ChatResult
}

// MARK: - Shared Types (wire-compatible with OpenAI)

public struct ChatMessage: Codable, Sendable, Equatable {
  public let role: String
  public let content: String

  public init(role: String, content: String) {
    self.role = role
    self.content = content
  }
}

public struct ChatOptions: Sendable {
  public var temperature: Double?
  public var maxTokens: Int?
  public var seed: UInt64?
  public var contextStrategy: String?
  public var contextMaxTurns: Int?
  public var permissive: Bool

  public init(
    temperature: Double? = nil,
    maxTokens: Int? = nil,
    seed: UInt64? = nil,
    contextStrategy: String? = nil,
    contextMaxTurns: Int? = nil,
    permissive: Bool = false
  ) {
    self.temperature = temperature
    self.maxTokens = maxTokens
    self.seed = seed
    self.contextStrategy = contextStrategy
    self.contextMaxTurns = contextMaxTurns
    self.permissive = permissive
  }
}

public struct ChatResult: Sendable {
  public let content: String
  public let usage: Usage?

  public init(content: String, usage: Usage?) {
    self.content = content
    self.usage = usage
  }
}

public struct Usage: Codable, Sendable, Equatable {
  public let promptTokens: Int
  public let completionTokens: Int
  public let totalTokens: Int

  public init(promptTokens: Int, completionTokens: Int, totalTokens: Int) {
    self.promptTokens = promptTokens
    self.completionTokens = completionTokens
    self.totalTokens = totalTokens
  }

  enum CodingKeys: String, CodingKey {
    case promptTokens = "prompt_tokens"
    case completionTokens = "completion_tokens"
    case totalTokens = "total_tokens"
  }
}

// MARK: - Engine Health

/// Describes an engine's origin and availability. Each engine fills in the
/// fields that make sense for its back-end.
public struct EngineHealth: Sendable {
  public let source: Source
  public let available: Bool
  public let detail: String
  public let contextSize: Int?

  public enum Source: Sendable, Equatable {
    case onDevice  // FoundationModels
    case remote(URL)  // HTTP endpoint
  }

  public init(source: Source, available: Bool, detail: String, contextSize: Int? = nil) {
    self.source = source
    self.available = available
    self.detail = detail
    self.contextSize = contextSize
  }
}

// MARK: - Local Engine (FoundationModels, in-process)

/// On-device inference via FoundationModels. No GUI app, no HTTP hop.
/// This is the default back-end when `--host` is not specified.
public final class LocalEngine: LLMEngine {
  private let model = SystemLanguageModel.default

  public init() {}

  public func health() async throws -> EngineHealth {
    let (available, detail) = Self.describe(model.availability)
    return EngineHealth(
      source: .onDevice,
      available: available,
      detail: detail,
      contextSize: model.contextSize
    )
  }

  public func chat(
    messages: [ChatMessage],
    options: ChatOptions,
    onDelta: @Sendable (String) -> Void
  ) async throws -> ChatResult {
    guard case .available = model.availability else {
      throw OGError.modelUnavailable(Self.describe(model.availability).1)
    }
    guard let lastUser = messages.last, lastUser.role == "user" else {
      throw OGError.usage("Last message must be from user")
    }

    let systemPrompt = messages.first(where: { $0.role == "system" })?.content
    let history = messages.filter { $0.role != "system" }.dropLast()
    let prompt = lastUser.content

    do {
      let session = try await buildSession(
        history: Array(history),
        systemPrompt: systemPrompt,
        prompt: prompt,
        options: options
      )
      let genOpts = makeGenerationOptions(options)
      let content = try await streamResponse(
        session: session, prompt: prompt, options: genOpts, onDelta: onDelta)
      let usage = await measureUsage(session: session, completion: content)
      return ChatResult(content: content, usage: usage)
    } catch let og as OGError {
      throw og
    } catch {
      throw OGError.fromGenerationError(error)
    }
  }

  // MARK: - Session building with token-budget trimming

  private func buildSession(
    history: [ChatMessage],
    systemPrompt: String?,
    prompt: String,
    options: ChatOptions
  ) async throws -> LanguageModelSession {
    let instrSegments: [Transcript.Segment] =
      systemPrompt.map {
        [.text(.init(content: $0))]
      } ?? []
    let instrEntry = Transcript.Entry.instructions(
      Transcript.Instructions(segments: instrSegments, toolDefinitions: [])
    )
    let promptEntry = Transcript.Entry.prompt(
      Transcript.Prompt(segments: [.text(.init(content: prompt))])
    )

    let budget = max(0, model.contextSize - outputReserve)
    guard await tokenCount([instrEntry, promptEntry]) <= budget else {
      throw OGError.contextOverflow("Prompt + system instructions exceed context window")
    }

    let historyEntries = Self.transcriptEntries(for: history)
    let trimmed = try await trimHistory(
      base: instrEntry, history: historyEntries, prompt: promptEntry,
      budget: budget, strategy: options.contextStrategy, maxTurns: options.contextMaxTurns)

    let sessionModel =
      options.permissive
      ? SystemLanguageModel(guardrails: .permissiveContentTransformations)
      : model

    return LanguageModelSession(
      model: sessionModel,
      transcript: Transcript(entries: [instrEntry] + trimmed)
    )
  }

  private func trimHistory(
    base: Transcript.Entry,
    history: [Transcript.Entry],
    prompt: Transcript.Entry,
    budget: Int,
    strategy rawStrategy: String?,
    maxTurns: Int?
  ) async throws -> [Transcript.Entry] {
    switch rawStrategy ?? "newest-first" {
    case "newest-first":
      return await trimBinary(
        base: base, history: history, prompt: prompt, budget: budget, fromEnd: true)
    case "oldest-first":
      return await trimBinary(
        base: base, history: history, prompt: prompt, budget: budget, fromEnd: false)
    case "sliding-window":
      let windowed = Array(history.suffix(maxTurns ?? history.count))
      return await trimBinary(
        base: base, history: windowed, prompt: prompt, budget: budget, fromEnd: true)
    case "summarize":
      return await trimWithSummary(
        base: base, history: history, prompt: prompt, budget: budget)
    case "strict":
      let all = [base] + history + [prompt]
      if await tokenCount(all) <= budget { return history }
      throw OGError.contextOverflow("History exceeds context with --context-strategy strict")
    default:
      throw OGError.usage("unknown context strategy: \(rawStrategy ?? "")")
    }
  }

  /// Compress old history into a short model-generated summary, keep recent
  /// turns verbatim. On any failure (no model, empty text, summary still
  /// overflows) degrade to `newest-first` so the caller never sees an error.
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
    guard history.count > 2, case .available = model.availability else {
      return await fallback()
    }

    // Reserve half the budget for recent verbatim turns.
    let halfBudget = budget / 2
    let recentCount = await maxSuffix(
      base: base, history: history, prompt: prompt, budget: halfBudget)
    let recent = Array(history.suffix(recentCount))
    let old = Array(history.dropLast(recentCount))
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
    if await tokenCount([base] + assembled + [prompt]) <= budget {
      return assembled
    }
    return await fallback()
  }

  /// Largest `k` for which `history.suffix(k)` fits with `base` + `prompt`.
  private func maxSuffix(
    base: Transcript.Entry,
    history: [Transcript.Entry],
    prompt: Transcript.Entry,
    budget: Int
  ) async -> Int {
    var lo = 0
    var hi = history.count
    while lo < hi {
      let mid = (lo + hi + 1) / 2
      if await tokenCount([base] + Array(history.suffix(mid)) + [prompt]) <= budget {
        lo = mid
      } else {
        hi = mid - 1
      }
    }
    return lo
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

  // MARK: - Streaming + usage

  private func streamResponse(
    session: LanguageModelSession,
    prompt: String,
    options: GenerationOptions,
    onDelta: @Sendable (String) -> Void
  ) async throws -> String {
    var full = ""
    var prev = ""
    for try await snapshot in session.streamResponse(to: prompt, options: options) {
      full = snapshot.content
      let delta = String(full.dropFirst(prev.count))
      if !delta.isEmpty { onDelta(delta) }
      prev = full
    }
    return full
  }

  private func measureUsage(session: LanguageModelSession, completion: String) async -> Usage? {
    guard #available(macOS 26.4, *) else { return nil }
    let all = Array(session.transcript)
    guard !all.isEmpty else { return nil }
    let total = (try? await model.tokenCount(for: all)) ?? 0
    let input = (try? await model.tokenCount(for: Array(all.dropLast()))) ?? 0
    return Usage(
      promptTokens: input,
      completionTokens: max(0, total - input),
      totalTokens: total
    )
  }

  // MARK: - Helpers

  private func tokenCount(_ entries: [Transcript.Entry]) async -> Int {
    guard !entries.isEmpty else { return 0 }
    if #available(macOS 26.4, *) {
      return (try? await model.tokenCount(for: entries)) ?? Self.fallbackCount(entries)
    }
    return Self.fallbackCount(entries)
  }

  private static func fallbackCount(_ entries: [Transcript.Entry]) -> Int {
    entries.reduce(0) {
      $0 + textSegments(of: $1).reduce(0) { $0 + max(1, $1.count / 4) }
    }
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

  private static func transcriptEntries(for messages: [ChatMessage]) -> [Transcript.Entry] {
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

  private func makeGenerationOptions(_ options: ChatOptions) -> GenerationOptions {
    let sampling: GenerationOptions.SamplingMode? = options.seed.map {
      .random(top: 50, seed: $0)
    }
    return GenerationOptions(
      sampling: sampling,
      temperature: options.temperature,
      maximumResponseTokens: options.maxTokens
    )
  }

  private static func describe(_ availability: SystemLanguageModel.Availability) -> (
    Bool, String
  ) {
    switch availability {
    case .available: (true, "available")
    case .unavailable(.appleIntelligenceNotEnabled):
      (false, "Apple Intelligence is not enabled in System Settings")
    case .unavailable(.deviceNotEligible):
      (false, "this device does not support Apple Intelligence")
    case .unavailable(.modelNotReady):
      (false, "model is downloading — try again later")
    case .unavailable:
      (false, "Apple Intelligence is unavailable")
    }
  }

  private let outputReserve = 512
}

// MARK: - Error Classification (FoundationModels)

extension OGError {
  /// Classify a thrown error from FoundationModels into a semantic OGError.
  static func fromGenerationError(_ error: Error) -> OGError {
    if let already = error as? OGError { return already }
    guard let gen = error as? LanguageModelSession.GenerationError else {
      return .runtime(error.localizedDescription)
    }
    return switch gen {
    case .exceededContextWindowSize: .contextOverflow("context window exceeded")
    case .guardrailViolation, .refusal: .guardrail("request blocked by safety guardrails")
    case .rateLimited: .rateLimited("rate limited — retry after a moment")
    case .concurrentRequests: .rateLimited("model busy with another request")
    case .assetsUnavailable: .modelUnavailable("model assets loading — try again")
    case .unsupportedGuide, .unsupportedLanguageOrLocale:
      .usage("unsupported generation guide or language")
    case .decodingFailure: .runtime("model output could not be decoded")
    @unknown default: .runtime(error.localizedDescription)
    }
  }
}
