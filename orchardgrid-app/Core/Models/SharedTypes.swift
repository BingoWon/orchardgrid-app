import Foundation
import FoundationModels
import OrchardGridCore
import SwiftUI

// MARK: - Capabilities

enum Capability: String, Codable, Sendable, CaseIterable {
  case chat, image, nlp, vision, speech, sound

  var displayName: String {
    switch self {
    case .chat: String(localized: "Chat")
    case .image: String(localized: "Image Generation")
    case .nlp: String(localized: "Text Analysis")
    case .vision: String(localized: "Vision")
    case .speech: String(localized: "Speech Recognition")
    case .sound: String(localized: "Sound Classification")
    }
  }

  var icon: String {
    switch self {
    case .chat: "bubble.left.and.text.bubble.right"
    case .image: "photo.artframe"
    case .nlp: "text.magnifyingglass"
    case .vision: "eye"
    case .speech: "waveform"
    case .sound: "speaker.wave.3"
    }
  }

}

// MARK: - JSON Schema Types

struct JSONSchemaDefinition: Codable, Sendable {
  let name: String
  let strict: Bool?
  let schema: JSONSchemaProperty
}

struct JSONSchemaProperty: Codable, Sendable {
  let type: String?
  let properties: [String: AnyCodable]?
  let required: [String]?
  let items: AnyCodable?
  let `enum`: [String]?
  let minimum: Double?
  let maximum: Double?
  let minItems: Int?
  let maxItems: Int?
  let additionalProperties: Bool?

  enum CodingKeys: String, CodingKey {
    case type, properties, required, items, `enum`, minimum, maximum
    case minItems, maxItems, additionalProperties
  }
}

struct AnyCodable: Codable, @unchecked Sendable {
  let value: Any

  init(_ value: Any) {
    self.value = value
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()

    if let dict = try? container.decode([String: AnyCodable].self) {
      value = dict.mapValues { $0.value }
    } else if let array = try? container.decode([AnyCodable].self) {
      value = array.map(\.value)
    } else if let string = try? container.decode(String.self) {
      value = string
    } else if let int = try? container.decode(Int.self) {
      value = int
    } else if let double = try? container.decode(Double.self) {
      value = double
    } else if let bool = try? container.decode(Bool.self) {
      value = bool
    } else {
      value = NSNull()
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()

    if let dict = value as? [String: Any] {
      try container.encode(dict.mapValues { AnyCodable($0) })
    } else if let array = value as? [Any] {
      try container.encode(array.map { AnyCodable($0) })
    } else if let string = value as? String {
      try container.encode(string)
    } else if let int = value as? Int {
      try container.encode(int)
    } else if let double = value as? Double {
      try container.encode(double)
    } else if let bool = value as? Bool {
      try container.encode(bool)
    } else {
      try container.encodeNil()
    }
  }

  func toJSONSchemaProperty() -> JSONSchemaProperty? {
    guard let dict = value as? [String: Any] else { return nil }

    return JSONSchemaProperty(
      type: dict["type"] as? String,
      properties: (dict["properties"] as? [String: Any])?.mapValues { AnyCodable($0) },
      required: dict["required"] as? [String],
      items: (dict["items"] as? [String: Any]).map { AnyCodable($0) },
      enum: dict["enum"] as? [String],
      minimum: dict["minimum"] as? Double,
      maximum: dict["maximum"] as? Double,
      minItems: dict["minItems"] as? Int,
      maxItems: dict["maxItems"] as? Int,
      additionalProperties: dict["additionalProperties"] as? Bool
    )
  }
}

// MARK: - OpenAI-Compatible API Types

struct ChatMessage: Codable, Sendable, TranscriptMessage {
  let role: String
  let content: String
}

struct ChatRequest: Codable, Sendable {
  let model: String
  let messages: [ChatMessage]
  let stream: Bool?
  let responseFormat: ResponseFormat?
  let temperature: Double?
  let maxTokens: Int?
  let seed: UInt64?
  let contextStrategy: String?
  let contextMaxTurns: Int?
  let permissive: Bool?

  enum CodingKeys: String, CodingKey {
    case model, messages, stream, temperature, seed, permissive
    case responseFormat = "response_format"
    case maxTokens = "max_tokens"
    case contextStrategy = "context_strategy"
    case contextMaxTurns = "context_max_turns"
  }
}

extension ChatRequest {
  var systemPrompt: String {
    messages.first { $0.role == "system" }?.content ?? Config.defaultSystemPrompt
  }

  var nonSystemMessages: [ChatMessage] {
    messages.filter { $0.role != "system" }
  }

  /// Build `SessionOptions` from wire parameters, falling back to defaults
  /// for anything the client didn't specify. The string ↔ enum mapping
  /// for `x_context_strategy` happens once here, at the HTTP boundary.
  var sessionOptions: SessionOptions {
    let strategy: ContextStrategy =
      switch contextStrategy {
      case "newest-first": .newestFirst
      case "oldest-first": .oldestFirst
      case "sliding-window": .slidingWindow(maxTurns: contextMaxTurns)
      case "summarize": .summarize
      case "strict": .strict
      default: .newestFirst
      }
    return SessionOptions(
      temperature: temperature,
      maxTokens: maxTokens,
      seed: seed,
      permissive: permissive ?? false,
      contextStrategy: strategy
    )
  }
}

struct ResponseFormat: Codable, Sendable {
  let type: String
  let jsonSchema: JSONSchemaDefinition?

  enum CodingKeys: String, CodingKey {
    case type
    case jsonSchema = "json_schema"
  }
}

// MARK: - Usage Types

struct TokenUsage: Codable, Sendable {
  let promptTokens: Int
  let completionTokens: Int
  let totalTokens: Int

  enum CodingKeys: String, CodingKey {
    case promptTokens = "prompt_tokens"
    case completionTokens = "completion_tokens"
    case totalTokens = "total_tokens"
  }
}

struct ChatResponse: Codable, Sendable {
  let id: String
  let object: String
  let created: Int
  let model: String
  let choices: [Choice]
  let usage: TokenUsage

  struct Choice: Codable, Sendable {
    let index: Int
    let message: ChatMessage
    let finishReason: String

    enum CodingKeys: String, CodingKey {
      case index, message
      case finishReason = "finish_reason"
    }
  }

  static func create(
    content: String,
    promptTokens: Int = 0,
    completionTokens: Int = 0
  ) -> ChatResponse {
    ChatResponse(
      id: "chatcmpl-\(UUID().uuidString.prefix(8))",
      object: "chat.completion",
      created: Int(Date().timeIntervalSince1970),
      model: "apple-intelligence",
      choices: [
        .init(
          index: 0,
          message: .init(role: "assistant", content: content),
          finishReason: "stop"
        )
      ],
      usage: .init(
        promptTokens: promptTokens,
        completionTokens: completionTokens,
        totalTokens: promptTokens + completionTokens
      )
    )
  }
}

struct StreamChunk: Codable, Sendable {
  let id: String
  let object: String
  let created: Int
  let model: String
  let choices: [Choice]
  let usage: TokenUsage?

  struct Choice: Codable, Sendable {
    let index: Int
    let delta: ChatMessage
    let finishReason: String?

    enum CodingKeys: String, CodingKey {
      case index, delta
      case finishReason = "finish_reason"
    }
  }

  static func delta(_ id: String, content: String) -> StreamChunk {
    StreamChunk(
      id: id,
      object: "chat.completion.chunk",
      created: Int(Date().timeIntervalSince1970),
      model: "apple-intelligence",
      choices: [
        .init(
          index: 0,
          delta: .init(role: "assistant", content: content),
          finishReason: nil
        )
      ],
      usage: nil
    )
  }

  static func end(
    _ id: String,
    finishReason: String = "stop",
    usage: TokenUsage? = nil
  ) -> StreamChunk {
    StreamChunk(
      id: id,
      object: "chat.completion.chunk",
      created: Int(Date().timeIntervalSince1970),
      model: "apple-intelligence",
      choices: [
        .init(
          index: 0,
          delta: .init(role: "assistant", content: ""),
          finishReason: finishReason
        )
      ],
      usage: usage
    )
  }
}

struct ModelsResponse: Codable, Sendable {
  let object: String
  let data: [Model]

  struct Model: Codable, Sendable {
    let id: String
    let object: String
    let created: Int
    let ownedBy: String

    enum CodingKeys: String, CodingKey {
      case id, object, created
      case ownedBy = "owned_by"
    }
  }
}

struct ErrorResponse: Codable, Sendable {
  let error: ErrorDetail

  struct ErrorDetail: Codable, Sendable {
    let message: String
    let type: String
    let code: String?
  }
}

// MARK: - Image Generation Types

struct ImageRequest: Codable, Sendable {
  let prompt: String
  let n: Int?
  let style: String?
  let responseFormat: String?

  enum CodingKeys: String, CodingKey {
    case prompt, n, style
    case responseFormat = "response_format"
  }
}

struct ImageResponse: Codable, Sendable {
  let created: Int
  let data: [ImageData]

  struct ImageData: Codable, Sendable {
    let b64Json: String

    enum CodingKeys: String, CodingKey {
      case b64Json = "b64_json"
    }
  }
}

// MARK: - AI Availability Helpers

extension SystemLanguageModel.Availability {
  var statusIcon: String {
    switch self {
    case .available:
      "checkmark.circle.fill"
    case .unavailable(.modelNotReady):
      "arrow.down.circle"
    default:
      "exclamationmark.triangle.fill"
    }
  }

  var statusColor: Color {
    switch self {
    case .available:
      .green
    case .unavailable(.modelNotReady):
      .blue
    default:
      .orange
    }
  }

  var statusTitle: String {
    switch self {
    case .available:
      String(localized: "Apple Intelligence Ready")
    case .unavailable(.deviceNotEligible):
      String(localized: "Device Not Supported")
    case .unavailable(.appleIntelligenceNotEnabled):
      String(localized: "Apple Intelligence Not Enabled")
    case .unavailable(.modelNotReady):
      String(localized: "Downloading Model...")
    case .unavailable:
      String(localized: "Apple Intelligence Unavailable")
    }
  }
}
