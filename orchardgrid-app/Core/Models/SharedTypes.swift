import Foundation

// MARK: - Capabilities

enum Capability: String, Codable, Sendable, CaseIterable {
  case chat, image, nlp, vision, speech, sound

  var displayName: String {
    switch self {
    case .chat: "Chat"
    case .image: "Image Generation"
    case .nlp: "Text Analysis"
    case .vision: "Vision"
    case .speech: "Speech Recognition"
    case .sound: "Sound Classification"
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

struct AnyCodable: Codable, Sendable {
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

struct ChatMessage: Codable, Sendable {
  let role: String
  let content: String
}

struct ChatRequest: Codable, Sendable {
  let model: String
  let messages: [ChatMessage]
  let stream: Bool?
  let responseFormat: ResponseFormat?

  enum CodingKeys: String, CodingKey {
    case model, messages, stream
    case responseFormat = "response_format"
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

struct ChatResponse: Codable, Sendable {
  let id: String
  let object: String
  let created: Int
  let model: String
  let choices: [Choice]
  let usage: Usage

  struct Choice: Codable, Sendable {
    let index: Int
    let message: ChatMessage
    let finishReason: String

    enum CodingKeys: String, CodingKey {
      case index, message
      case finishReason = "finish_reason"
    }
  }

  struct Usage: Codable, Sendable {
    let promptTokens: Int
    let completionTokens: Int
    let totalTokens: Int

    enum CodingKeys: String, CodingKey {
      case promptTokens = "prompt_tokens"
      case completionTokens = "completion_tokens"
      case totalTokens = "total_tokens"
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
      ]
    )
  }

  static func end(_ id: String, finishReason: String = "stop") -> StreamChunk {
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
      ]
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
