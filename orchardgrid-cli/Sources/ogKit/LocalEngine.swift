import Foundation
@preconcurrency import FoundationModels
import OrchardGridCore

// MARK: - LocalEngine
//
// On-device inference via FoundationModels. No GUI app, no HTTP hop.
// Default back-end when `--host` is not specified. Context trimming,
// token counting, and transcript assembly are delegated to
// `OrchardGridCore.ContextTools` so the CLI and the app share a single
// implementation.

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
      let usage = await measureUsage(session: session)
      return ChatResult(content: content, usage: usage)
    } catch let og as OGError {
      throw og
    } catch {
      throw OGError.fromModelError(error)
    }
  }

  // MARK: - Session building

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

    let budget = max(0, model.contextSize - ContextBudget.defaultOutputReserve)
    guard await ContextTools.tokenCount([instrEntry, promptEntry], model: model) <= budget
    else {
      throw OGError.contextOverflow("Prompt + system instructions exceed context window")
    }

    let historyEntries = ContextTools.transcriptEntries(from: history)
    let strategy = try parseStrategy(
      raw: options.contextStrategy, maxTurns: options.contextMaxTurns)
    let trimmed: [Transcript.Entry]
    do {
      trimmed = try await ContextTools.trim(
        strategy, base: instrEntry, history: historyEntries,
        prompt: promptEntry, budget: budget, model: model)
    } catch is ContextOverflowError {
      throw OGError.contextOverflow(
        "History exceeds context with --context-strategy strict")
    }

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

  /// Map the CLI's string-form `--context-strategy` value (validated at
  /// parse time to one of the five known tokens) onto the typed
  /// `ContextStrategy` the shared package expects.
  private func parseStrategy(
    raw: String?, maxTurns: Int?
  ) throws -> ContextStrategy {
    switch raw ?? "newest-first" {
    case "newest-first": .newestFirst
    case "oldest-first": .oldestFirst
    case "sliding-window": .slidingWindow(maxTurns: maxTurns)
    case "summarize": .summarize
    case "strict": .strict
    default: throw OGError.usage("unknown context strategy: \(raw ?? "")")
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

  private func measureUsage(session: LanguageModelSession) async -> Usage? {
    guard let u = await ContextTools.measureUsage(session: session, model: model)
    else { return nil }
    return Usage(promptTokens: u.prompt, completionTokens: u.completion, totalTokens: u.total)
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
}
