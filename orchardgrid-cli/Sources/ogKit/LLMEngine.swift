import Foundation
@preconcurrency import FoundationModels
import OrchardGridCore

// MARK: - Engine Protocol

/// A unified interface over on-device (FoundationModels) and remote (HTTP)
/// inference. Both back-ends stream content chunks and return usage counts.
public protocol LLMEngine: Sendable {
  /// Describe the engine's source + availability. Used by `og --model-info`.
  func health() async throws -> EngineHealth

  /// Run a streaming chat completion. `onDelta` fires for each content chunk.
  /// Pass an `MCPManager` to enable tool calling — only supported by
  /// `LocalEngine`; remote paths throw `OGError.usage`.
  func chat(
    messages: [ChatMessage],
    options: ChatOptions,
    mcp: MCPManager?,
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
    mcp: MCPManager?,
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
    let tools: [any Tool] = await mcp?.tools ?? []

    do {
      let session = try await buildSession(
        history: Array(history),
        systemPrompt: systemPrompt,
        prompt: prompt,
        options: options,
        tools: tools
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
    options: ChatOptions,
    tools: [any Tool]
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
    guard await ContextTools.tokenCount([instrEntry, promptEntry], model: model) <= budget else {
      throw OGError.contextOverflow("Prompt + system instructions exceed context window")
    }

    let historyEntries = ContextTools.transcriptEntries(
      from: history.map { (role: $0.role, content: $0.content) })
    let trimmed = try await trimHistory(
      base: instrEntry, history: historyEntries, prompt: promptEntry,
      budget: budget, strategy: options.contextStrategy, maxTurns: options.contextMaxTurns)

    let sessionModel =
      options.permissive
      ? SystemLanguageModel(guardrails: .permissiveContentTransformations)
      : model

    return LanguageModelSession(
      model: sessionModel,
      tools: tools,
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
      return await ContextTools.trimBinary(
        base: base, history: history, prompt: prompt,
        budget: budget, fromEnd: true, model: model)
    case "oldest-first":
      return await ContextTools.trimBinary(
        base: base, history: history, prompt: prompt,
        budget: budget, fromEnd: false, model: model)
    case "sliding-window":
      let windowed = Array(history.suffix(maxTurns ?? history.count))
      return await ContextTools.trimBinary(
        base: base, history: windowed, prompt: prompt,
        budget: budget, fromEnd: true, model: model)
    case "summarize":
      return await ContextTools.trimWithSummary(
        base: base, history: history, prompt: prompt,
        budget: budget, model: model)
    case "strict":
      let all = [base] + history + [prompt]
      if await ContextTools.tokenCount(all, model: model) <= budget { return history }
      throw OGError.contextOverflow("History exceeds context with --context-strategy strict")
    default:
      throw OGError.usage("unknown context strategy: \(rawStrategy ?? "")")
    }
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
