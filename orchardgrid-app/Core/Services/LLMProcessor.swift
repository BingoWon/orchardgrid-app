/**
 * LLMProcessor.swift
 * OrchardGrid LLM Processing Service
 *
 * Shared logic for processing LLM requests across APIServer and WebSocketClient
 */

import Foundation
@preconcurrency import FoundationModels

/// Shared LLM processing service
@MainActor
final class LLMProcessor {
  private let model = SystemLanguageModel.default

  /// Model availability
  var availability: SystemLanguageModel.Availability {
    model.availability
  }

  /// Check if model is available
  var isAvailable: Bool {
    if case .available = model.availability {
      return true
    }
    return false
  }

  /// Process a chat request with streaming support
  func processRequest(
    messages: [ChatMessage],
    systemPrompt: String,
    responseFormat: ResponseFormat?,
    onChunk: @escaping (String) -> Void
  ) async throws -> String {
    guard case .available = model.availability else {
      throw LLMError.modelUnavailable
    }

    guard let lastMessage = messages.last, lastMessage.role == "user" else {
      throw LLMError.invalidRequest("Last message must be from user")
    }

    let transcript = buildTranscript(from: messages, systemPrompt: systemPrompt)
    let session = LanguageModelSession(transcript: transcript)

    // Handle JSON schema if specified
    if let responseFormat,
       responseFormat.type == "json_schema",
       let jsonSchema = responseFormat.json_schema
    {
      let validatedSchema = try await MainActor.run {
        let converter = SchemaConverter()
        return try converter.convert(jsonSchema)
      }

      let stream = session.streamResponse(to: lastMessage.content, schema: validatedSchema)
      var fullContent = ""
      var previousContent = ""

      for try await snapshot in stream {
        fullContent = snapshot.content.jsonString
        let delta = String(fullContent.dropFirst(previousContent.count))

        if !delta.isEmpty {
          onChunk(delta)
        }

        previousContent = fullContent
      }
      return fullContent
    } else {
      let stream = session.streamResponse(to: lastMessage.content)
      var fullContent = ""
      var previousContent = ""

      for try await snapshot in stream {
        fullContent = snapshot.content
        let delta = String(fullContent.dropFirst(previousContent.count))

        if !delta.isEmpty {
          onChunk(delta)
        }

        previousContent = fullContent
      }
      return fullContent
    }
  }

  /// Process a chat request without streaming
  func processRequest(
    messages: [ChatMessage],
    systemPrompt: String,
    responseFormat: ResponseFormat?
  ) async throws -> String {
    guard case .available = model.availability else {
      throw LLMError.modelUnavailable
    }

    guard let lastMessage = messages.last, lastMessage.role == "user" else {
      throw LLMError.invalidRequest("Last message must be from user")
    }

    let transcript = buildTranscript(from: messages, systemPrompt: systemPrompt)
    let session = LanguageModelSession(transcript: transcript)

    // Handle JSON schema if specified
    if let responseFormat,
       responseFormat.type == "json_schema",
       let jsonSchema = responseFormat.json_schema
    {
      let validatedSchema = try await MainActor.run {
        let converter = SchemaConverter()
        return try converter.convert(jsonSchema)
      }
      let response = try await session.respond(to: lastMessage.content, schema: validatedSchema)
      return response.content.jsonString
    } else {
      let response = try await session.respond(to: lastMessage.content)
      return response.content
    }
  }

  /// Build transcript from messages
  private func buildTranscript(
    from messages: [ChatMessage],
    systemPrompt: String
  ) -> Transcript {
    var entries: [Transcript.Entry] = []

    let instructions = Transcript.Instructions(
      segments: [.text(.init(content: systemPrompt))],
      toolDefinitions: []
    )
    entries.append(.instructions(instructions))

    for message in messages {
      switch message.role {
      case "user":
        let prompt = Transcript.Prompt(
          segments: [.text(.init(content: message.content))]
        )
        entries.append(.prompt(prompt))

      case "assistant":
        let response = Transcript.Response(
          assetIDs: [],
          segments: [.text(.init(content: message.content))]
        )
        entries.append(.response(response))

      default:
        break
      }
    }

    return Transcript(entries: entries)
  }
}

/// LLM processing errors
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
