import Foundation
@preconcurrency import FoundationModels
import OrchardGridCore

// MARK: - Engine Protocol

/// A unified interface over on-device (FoundationModels) and remote
/// (HTTP) inference. Both back-ends stream content chunks and return
/// usage counts.
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

// MARK: - Shared DTOs (wire-compatible with OpenAI)

public struct ChatMessage: Codable, Sendable, Equatable, TranscriptMessage {
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

/// Describes an engine's origin and availability. Each engine fills in
/// the fields that make sense for its back-end.
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
