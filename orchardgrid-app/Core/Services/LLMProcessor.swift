import Foundation
@preconcurrency import FoundationModels
import OrchardGridCore

// MARK: - LLM Result

struct LLMResult: Sendable {
  let content: String
  let promptTokens: Int
  let completionTokens: Int
  var totalTokens: Int { promptTokens + completionTokens }
}

// MARK: - Session Options

/// Per-request generation + context parameters forwarded from the HTTP
/// request all the way into the FoundationModels call. `contextStrategy`
/// is `OrchardGridCore.ContextStrategy` directly — CLI and app share the
/// same 5-case enum, parsing happens at the boundary in `SharedTypes`.
struct SessionOptions: Sendable {
  let temperature: Double?
  let maxTokens: Int?
  let seed: UInt64?
  let permissive: Bool
  let contextStrategy: ContextStrategy

  nonisolated static let defaults = SessionOptions(
    temperature: nil, maxTokens: nil, seed: nil,
    permissive: false, contextStrategy: .newestFirst
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
          content = try await Retry.withRetry(
            isRetryable: { LLMError.classify($0).isRetryable }
          ) {
            try await session.respond(to: prompt, schema: schema, options: genOpts).content
              .jsonString
          }
        }
      } else if let onChunk {
        content = try await streamText(
          session: session, prompt: prompt, options: genOpts, onChunk: onChunk)
      } else {
        content = try await Retry.withRetry(
          isRetryable: { LLMError.classify($0).isRetryable }
        ) {
          try await session.respond(to: prompt, options: genOpts).content
        }
      }

      // OpenAI spec: `response_format: { "type": "json_object" }`
      // requires the assistant message to be raw JSON. Apple's model
      // often wraps in ```json ... ``` despite the prompt — strip it.
      // Streaming json_object is rare and harder to fix mid-chunk;
      // matches apfel's behaviour of stripping only on the final
      // accumulated string.
      let final =
        responseFormat?.type == "json_object"
        ? JSONFenceStripper.strip(content) : content

      return await measureUsage(content: final, session: session)
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

    let budget = max(0, contextSize - ContextBudget.defaultOutputReserve)
    guard await ContextTools.tokenCount([instrEntry, promptEntry], model: model) <= budget
    else {
      throw LLMError.contextOverflow
    }

    let historyEntries = ContextTools.transcriptEntries(from: history)
    let trimmed: [Transcript.Entry]
    do {
      trimmed = try await ContextTools.trim(
        options.contextStrategy,
        base: instrEntry, history: historyEntries,
        prompt: promptEntry, budget: budget, model: model)
    } catch is ContextOverflowError {
      throw LLMError.contextOverflow
    }

    let sessionModel =
      options.permissive
      ? SystemLanguageModel(guardrails: .permissiveContentTransformations)
      : model

    return LanguageModelSession(
      model: sessionModel,
      transcript: Transcript(entries: [instrEntry] + trimmed)
    )
  }

  // MARK: - Token Measurement (post-response)

  /// Compute prompt/completion split from the transcript after inference.
  /// Delegates to `ContextTools.measureUsage`; wraps the shared
  /// `TokenUsage` into the app-local `LLMResult` type.
  private func measureUsage(content: String, session: LanguageModelSession) async -> LLMResult {
    guard let u = await ContextTools.measureUsage(session: session, model: model)
    else {
      return LLMResult(content: content, promptTokens: 0, completionTokens: 0)
    }
    return LLMResult(content: content, promptTokens: u.prompt, completionTokens: u.completion)
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

}
