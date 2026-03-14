import Foundation
@preconcurrency import FoundationModels

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

  static func checkAvailability() -> Bool {
    if case .available = SystemLanguageModel.default.availability { return true }
    return false
  }

  /// Unified request handler — pass `onChunk` for streaming, omit for single response.
  func processRequest(
    messages: [ChatMessage],
    systemPrompt: String,
    responseFormat: ResponseFormat? = nil,
    onChunk: ((String) -> Void)? = nil
  ) async throws -> String {
    guard case .available = model.availability else {
      throw LLMError.modelUnavailable
    }
    guard let lastMessage = messages.last, lastMessage.role == "user" else {
      throw LLMError.invalidRequest("Last message must be from user")
    }

    let transcript = Self.buildTranscript(messages: messages, systemPrompt: systemPrompt)
    let session = LanguageModelSession(transcript: transcript)
    let prompt = lastMessage.content

    if let responseFormat, responseFormat.type == "json_schema",
       let jsonSchema = responseFormat.json_schema
    {
      let schema = try SchemaConverter().convert(jsonSchema)
      if let onChunk {
        return try await streamJSON(session: session, prompt: prompt, schema: schema, onChunk: onChunk)
      }
      return try await session.respond(to: prompt, schema: schema).content.jsonString
    }

    if let onChunk {
      return try await streamText(session: session, prompt: prompt, onChunk: onChunk)
    }
    return try await session.respond(to: prompt).content
  }

  // MARK: - Stream Helpers

  private func streamText(
    session: LanguageModelSession,
    prompt: String,
    onChunk: (String) -> Void
  ) async throws -> String {
    var full = "", prev = ""
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
    var full = "", prev = ""
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

    entries.append(.instructions(Transcript.Instructions(
      segments: [.text(.init(content: systemPrompt))],
      toolDefinitions: []
    )))

    for message in messages {
      switch message.role {
      case "user":
        entries.append(.prompt(Transcript.Prompt(
          segments: [.text(.init(content: message.content))]
        )))
      case "assistant":
        entries.append(.response(Transcript.Response(
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
    case let .invalidRequest(message):
      "Invalid request: \(message)"
    case let .processingFailed(message):
      "Processing failed: \(message)"
    }
  }
}
