import Foundation
@preconcurrency import FoundationModels

// MARK: - LLM Result

struct LLMResult: Sendable {
  let content: String
  let promptTokens: Int
  let completionTokens: Int
  var totalTokens: Int { promptTokens + completionTokens }
}

// MARK: - LLM Processor

@MainActor
final class LLMProcessor {
  private let model = SystemLanguageModel.default

  var availability: SystemLanguageModel.Availability {
    model.availability
  }

  var isAvailable: Bool {
    if case .available = model.availability { return true }
    return false
  }

  var contextSize: Int {
    get async {
      (try? await model.contextSize) ?? 4096
    }
  }

  /// Unified request handler — pass `onChunk` for streaming, omit for single response.
  func processRequest(
    messages: [ChatMessage],
    systemPrompt: String,
    responseFormat: ResponseFormat? = nil,
    onChunk: ((String) -> Void)? = nil
  ) async throws -> LLMResult {
    guard case .available = model.availability else {
      throw LLMError.modelUnavailable
    }
    guard let lastMessage = messages.last, lastMessage.role == "user" else {
      throw LLMError.invalidRequest("Last message must be from user")
    }

    let transcript = Self.buildTranscript(messages: messages, systemPrompt: systemPrompt)
    let session = LanguageModelSession(transcript: transcript)
    let prompt = lastMessage.content

    let content: String

    if let responseFormat, responseFormat.type == "json_schema",
      let jsonSchema = responseFormat.jsonSchema
    {
      let schema = try SchemaConverter().convert(jsonSchema)
      if let onChunk {
        content = try await streamJSON(
          session: session, prompt: prompt, schema: schema, onChunk: onChunk)
      } else {
        content = try await session.respond(to: prompt, schema: schema).content.jsonString
      }
    } else if let onChunk {
      content = try await streamText(session: session, prompt: prompt, onChunk: onChunk)
    } else {
      content = try await session.respond(to: prompt).content
    }

    return await measureUsage(content: content, session: session)
  }

  // MARK: - Token Measurement

  private func measureUsage(content: String, session: LanguageModelSession) async -> LLMResult {
    let totalTokens = (try? await model.tokenUsage(for: session.transcript).tokenCount) ?? 0
    let completionTokens = (try? await model.tokenUsage(for: Prompt(content)).tokenCount) ?? 0
    let promptTokens = max(0, totalTokens - completionTokens)

    return LLMResult(
      content: content,
      promptTokens: promptTokens,
      completionTokens: completionTokens
    )
  }

  /// Measure token usage for instructions with optional tools.
  func measureInstructions(
    _ text: String,
    tools: [any Tool] = []
  ) async -> Int {
    let instructions = Instructions(text)
    if tools.isEmpty {
      return (try? await model.tokenUsage(for: instructions).tokenCount) ?? 0
    }
    return (try? await model.tokenUsage(for: instructions, tools: tools).tokenCount) ?? 0
  }

  /// Measure token usage for a prompt string.
  func measurePrompt(_ text: String) async -> Int {
    (try? await model.tokenUsage(for: Prompt(text)).tokenCount) ?? 0
  }

  // MARK: - Stream Helpers

  private func streamText(
    session: LanguageModelSession,
    prompt: String,
    onChunk: (String) -> Void
  ) async throws -> String {
    var full = ""
    var prev = ""
    for try await snapshot in session.streamResponse(to: prompt) {
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
    onChunk: (String) -> Void
  ) async throws -> String {
    var full = ""
    var prev = ""
    for try await snapshot in session.streamResponse(to: prompt, schema: schema) {
      full = snapshot.content.jsonString
      let delta = String(full.dropFirst(prev.count))
      if !delta.isEmpty { onChunk(delta) }
      prev = full
    }
    return full
  }

  // MARK: - Transcript

  static func buildTranscript(
    messages: [ChatMessage],
    systemPrompt: String
  ) -> Transcript {
    var entries: [Transcript.Entry] = []

    entries.append(
      .instructions(
        Transcript.Instructions(
          segments: [.text(.init(content: systemPrompt))],
          toolDefinitions: []
        )))

    for message in messages {
      switch message.role {
      case "user":
        entries.append(
          .prompt(
            Transcript.Prompt(
              segments: [.text(.init(content: message.content))]
            )))
      case "assistant":
        entries.append(
          .response(
            Transcript.Response(
              assetIDs: [],
              segments: [.text(.init(content: message.content))]
            )))
      default:
        break
      }
    }

    return Transcript(entries: entries)
  }
}

// MARK: - Errors

enum LLMError: Error, LocalizedError {
  case modelUnavailable
  case invalidRequest(String)
  case processingFailed(String)

  var errorDescription: String? {
    switch self {
    case .modelUnavailable:
      "Model is not available"
    case .invalidRequest(let message):
      "Invalid request: \(message)"
    case .processingFailed(let message):
      "Processing failed: \(message)"
    }
  }
}
