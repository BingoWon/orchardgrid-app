import Foundation
import OrchardGridCore

// MARK: - Remote Engine
//
// HTTP engine talking to an OpenAI-compatible OrchardGrid endpoint —
// either a LAN peer or `https://orchardgrid.com`. Used whenever `--host`
// is specified; otherwise `LocalEngine` runs in-process.

public struct RemoteEngine: LLMEngine {
  public let base: URL
  public let token: String?
  private let session = URLSession.shared

  public init(host: String, token: String?) throws {
    guard let url = URL(string: host) else { throw OGError.usage("invalid host: \(host)") }
    self.base = url
    self.token = token
  }

  // MARK: - Endpoints

  public func health() async throws -> EngineHealth {
    var request = URLRequest(url: base.appendingPathComponent("health"))
    addAuth(&request)
    do {
      let (data, response) = try await session.data(for: request)
      try check(response, body: data)
      let info = try JSONDecoder().decode(RemoteHealth.self, from: data)
      return EngineHealth(
        source: .remote(base),
        available: info.available,
        detail: info.status,
        contextSize: nil
      )
    } catch let og as OGError {
      throw og
    } catch {
      throw OGError.serverUnreachable
    }
  }

  public func chat(
    messages: [ChatMessage],
    options: ChatOptions,
    mcp: MCPManager?,
    onDelta: @Sendable (String) -> Void
  ) async throws -> ChatResult {
    if mcp != nil {
      throw OGError.usage("--mcp requires on-device inference; remove --host to run locally")
    }
    let body = ChatRequestBody(messages: messages, options: options)
    var request = URLRequest(url: base.appendingPathComponent("v1/chat/completions"))
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    addAuth(&request)
    request.httpBody = try JSONEncoder().encode(body)
    let frozen = request

    // Retry only the connection / pre-stream phase. Once bytes start
    // flowing, retrying would duplicate `onDelta` output.
    let bytes = try await Retry.withRetry(
      isRetryable: { ($0 as? OGError)?.isRetryable == true }
    ) {
      try await self.openStream(request: frozen)
    }

    var content = ""
    var usage: Usage?
    for try await line in bytes.lines {
      guard line.hasPrefix("data: ") else { continue }
      let payload = String(line.dropFirst(6))
      if payload == "[DONE]" { break }
      guard let data = payload.data(using: .utf8),
        let chunk = try? JSONDecoder().decode(StreamChunk.self, from: data)
      else { continue }
      if let delta = chunk.choices.first?.delta.content, !delta.isEmpty {
        content += delta
        onDelta(delta)
      }
      if let u = chunk.usage { usage = u }
    }
    return ChatResult(content: content, usage: usage)
  }

  // MARK: - Helpers

  private func openStream(request: URLRequest) async throws -> URLSession.AsyncBytes {
    let bytes: URLSession.AsyncBytes
    let response: URLResponse
    do {
      (bytes, response) = try await session.bytes(for: request)
    } catch {
      throw OGError.serverUnreachable
    }
    guard let http = response as? HTTPURLResponse else { throw OGError.runtime("invalid response") }
    if !(200...299).contains(http.statusCode) {
      var errData = Data()
      for try await byte in bytes { errData.append(byte) }
      throw OGError.fromHTTP(status: http.statusCode, body: errData)
    }
    return bytes
  }

  private func addAuth(_ request: inout URLRequest) {
    if let token, !token.isEmpty {
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
  }

  private func check(_ response: URLResponse, body: Data) throws {
    guard let http = response as? HTTPURLResponse else {
      throw OGError.runtime("invalid response")
    }
    if !(200...299).contains(http.statusCode) {
      throw OGError.fromHTTP(status: http.statusCode, body: body)
    }
  }
}

// MARK: - Wire Types (private to this file)

/// Shape of `GET /health` on an OrchardGrid-compatible server.
private struct RemoteHealth: Decodable {
  let status: String
  let model: String
  let available: Bool
}

/// Request body for `POST /v1/chat/completions`.
struct ChatRequestBody: Encodable {
  let model = AppIdentity.modelName
  let stream = true
  let messages: [ChatMessage]
  let temperature: Double?
  let maxTokens: Int?
  let seed: UInt64?
  let contextStrategy: String?
  let contextMaxTurns: Int?
  let permissive: Bool?

  init(messages: [ChatMessage], options: ChatOptions) {
    self.messages = messages
    self.temperature = options.temperature
    self.maxTokens = options.maxTokens
    self.seed = options.seed
    self.contextStrategy = options.contextStrategy
    self.contextMaxTurns = options.contextMaxTurns
    self.permissive = options.permissive ? true : nil
  }

  enum CodingKeys: String, CodingKey {
    case model, messages, stream, temperature, seed, permissive
    case maxTokens = "max_tokens"
    case contextStrategy = "context_strategy"
    case contextMaxTurns = "context_max_turns"
  }
}

struct StreamChunk: Decodable {
  let choices: [Choice]
  let usage: Usage?

  struct Choice: Decodable {
    let delta: Delta
    struct Delta: Decodable { let content: String? }
  }
}

// MARK: - Engine Factory

public enum EngineFactory {
  /// Build the right engine based on CLI arguments.
  /// No `--host` → `LocalEngine` (apfel-style, in-process FoundationModels).
  /// `--host` set  → `RemoteEngine` (HTTP to LAN peer or cloud).
  public static func make(host: String?, token: String?) throws -> LLMEngine {
    if let host, !host.isEmpty {
      return try RemoteEngine(host: host, token: token)
    }
    return LocalEngine()
  }
}
