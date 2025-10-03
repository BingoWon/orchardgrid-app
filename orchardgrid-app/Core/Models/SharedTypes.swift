/**
 * SharedTypes.swift
 * OrchardGrid Shared Type Definitions
 *
 * All types used across multiple files are defined here
 * to ensure proper type resolution by SourceKit and Swift compiler.
 *
 * Organization:
 * 1. JSON Schema Types
 * 2. API Request/Response Types
 * 3. WebSocket Message Types
 */

import Foundation
@preconcurrency import FoundationModels

// MARK: - JSON Schema Types

/// JSON Schema definition for structured output
struct JSONSchemaDefinition: Codable, Sendable {
  let name: String
  let strict: Bool?
  let schema: JSONSchemaProperty
}

/// JSON Schema property definition
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

/// Helper to handle Any in Codable
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
}

// MARK: - API Request/Response Types

/// Chat message in conversation
struct ChatMessage: Codable, Sendable {
  let role: String
  let content: String
}

/// Chat completion request
struct ChatRequest: Codable, Sendable {
  let model: String
  let messages: [ChatMessage]
  let stream: Bool?
  let response_format: ResponseFormat?
}

/// Response format specification
struct ResponseFormat: Codable, Sendable {
  let type: String
  let json_schema: JSONSchemaDefinition?
}

/// Chat completion response
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
}

/// Streaming response chunk
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
}

/// Models list response
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

/// Error response
struct ErrorResponse: Codable, Sendable {
  let error: ErrorDetail

  struct ErrorDetail: Codable, Sendable {
    let message: String
    let type: String
    let code: String?
  }
}

// MARK: - WebSocket Message Types

/// Task message from platform
struct TaskMessage: Codable, Sendable {
  let id: String
  let type: String // "task"
  let payload: ChatRequest
}

/// Response message to platform
struct ResponseMessage: Codable, Sendable {
  let id: String
  let type: String // "response"
  let payload: ChatResponse
}

/// Stream chunk message
struct StreamChunkMessage: Codable, Sendable {
  let id: String
  let type: String // "stream"
  let delta: String
}

/// Stream end message
struct StreamEndMessage: Codable, Sendable {
  let id: String
  let type: String // "stream_end"
}

/// Error message
struct ErrorMessage: Codable, Sendable {
  let id: String
  let type: String // "error"
  let error: String
}

/// Heartbeat message
struct HeartbeatMessage: Codable, Sendable {
  let type: String // "heartbeat"
}

// MARK: - AnyCodable Extensions

extension AnyCodable {
  /// Convert AnyCodable to JSONSchemaProperty
  func toJSONSchemaProperty() -> JSONSchemaProperty? {
    guard let dict = value as? [String: Any] else { return nil }

    let type = dict["type"] as? String
    let properties = (dict["properties"] as? [String: Any])?.mapValues { AnyCodable($0) }
    let required = dict["required"] as? [String]
    let items = (dict["items"] as? [String: Any]).map { AnyCodable($0) }
    let enumValues = dict["enum"] as? [String]
    let minimum = dict["minimum"] as? Double
    let maximum = dict["maximum"] as? Double
    let minItems = dict["minItems"] as? Int
    let maxItems = dict["maxItems"] as? Int
    let additionalProperties = dict["additionalProperties"] as? Bool

    return JSONSchemaProperty(
      type: type,
      properties: properties,
      required: required,
      items: items,
      enum: enumValues,
      minimum: minimum,
      maximum: maximum,
      minItems: minItems,
      maxItems: maxItems,
      additionalProperties: additionalProperties
    )
  }
}
