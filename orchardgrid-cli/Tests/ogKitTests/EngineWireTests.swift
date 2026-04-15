import Foundation
import Testing

@testable import ogKit

@Suite("Engine wire coding")
struct EngineWireTests {

  private func json(_ encodable: some Encodable) throws -> [String: Any] {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(encodable)
    let obj = try JSONSerialization.jsonObject(with: data)
    return obj as! [String: Any]
  }

  // MARK: - ChatRequestBody encoding

  @Test("defaults omit all optional fields")
  func defaultsOmitOptionals() throws {
    let body = ChatRequestBody(
      messages: [ChatMessage(role: "user", content: "hi")],
      options: ChatOptions()
    )
    let dict = try json(body)

    #expect(dict["model"] as? String == "apple-foundationmodel")
    #expect(dict["stream"] as? Bool == true)
    #expect(dict["temperature"] == nil)
    #expect(dict["max_tokens"] == nil)
    #expect(dict["seed"] == nil)
    #expect(dict["context_strategy"] == nil)
    #expect(dict["context_max_turns"] == nil)
    #expect(dict["permissive"] == nil)
  }

  @Test("all options emit snake_case keys with correct values")
  func allOptionsEmitSnakeCase() throws {
    let body = ChatRequestBody(
      messages: [ChatMessage(role: "user", content: "hi")],
      options: ChatOptions(
        temperature: 0.5,
        maxTokens: 256,
        seed: 42,
        contextStrategy: "strict",
        contextMaxTurns: 8,
        permissive: true
      )
    )
    let dict = try json(body)

    #expect(dict["temperature"] as? Double == 0.5)
    #expect(dict["max_tokens"] as? Int == 256)
    #expect(dict["seed"] as? UInt64 == 42)
    #expect(dict["context_strategy"] as? String == "strict")
    #expect(dict["context_max_turns"] as? Int == 8)
    #expect(dict["permissive"] as? Bool == true)
  }

  @Test("permissive=false is omitted (not serialized as false)")
  func permissiveFalseOmitted() throws {
    let body = ChatRequestBody(
      messages: [], options: ChatOptions(permissive: false))
    let dict = try json(body)
    #expect(dict["permissive"] == nil)
  }

  @Test("messages round-trip with role + content")
  func messagesRoundTrip() throws {
    let body = ChatRequestBody(
      messages: [
        ChatMessage(role: "system", content: "be brief"),
        ChatMessage(role: "user", content: "hi"),
      ],
      options: ChatOptions()
    )
    let dict = try json(body)
    let messages = dict["messages"] as? [[String: String]] ?? []
    #expect(messages.count == 2)
    #expect(messages[0] == ["role": "system", "content": "be brief"])
    #expect(messages[1] == ["role": "user", "content": "hi"])
  }

  // MARK: - StreamChunk decoding

  @Test("decode delta chunk")
  func decodeDelta() throws {
    let data = Data(
      """
      {"choices":[{"delta":{"content":"Hello"}}]}
      """.utf8)
    let chunk = try JSONDecoder().decode(StreamChunk.self, from: data)
    #expect(chunk.choices.first?.delta.content == "Hello")
    #expect(chunk.usage == nil)
  }

  @Test("decode chunk with usage (end-of-stream)")
  func decodeEndChunk() throws {
    let data = Data(
      """
      {"choices":[{"delta":{"content":""}}],
       "usage":{"prompt_tokens":10,"completion_tokens":20,"total_tokens":30}}
      """.utf8)
    let chunk = try JSONDecoder().decode(StreamChunk.self, from: data)
    #expect(chunk.usage?.promptTokens == 10)
    #expect(chunk.usage?.completionTokens == 20)
    #expect(chunk.usage?.totalTokens == 30)
  }

  @Test("decode empty delta")
  func decodeEmptyDelta() throws {
    let data = Data(
      """
      {"choices":[{"delta":{}}]}
      """.utf8)
    let chunk = try JSONDecoder().decode(StreamChunk.self, from: data)
    #expect(chunk.choices.first?.delta.content == nil)
  }

  // MARK: - Usage round-trip

  @Test("Usage uses snake_case on the wire and camelCase in Swift")
  func usageCoding() throws {
    let data = Data(
      """
      {"prompt_tokens":1,"completion_tokens":2,"total_tokens":3}
      """.utf8)
    let usage = try JSONDecoder().decode(Usage.self, from: data)
    #expect(usage == Usage(promptTokens: 1, completionTokens: 2, totalTokens: 3))
  }

  // MARK: - JSONOutput (CLI response envelope)

  @Test("JSONOutput encodes content + optional usage")
  func jsonOutput() throws {
    let out = JSONOutput(
      content: "Hi", usage: Usage(promptTokens: 1, completionTokens: 2, totalTokens: 3))
    let dict = try json(out)
    #expect(dict["content"] as? String == "Hi")
    let usage = dict["usage"] as? [String: Int]
    #expect(usage?["prompt_tokens"] == 1)
    #expect(usage?["completion_tokens"] == 2)
    #expect(usage?["total_tokens"] == 3)
  }

  @Test("JSONOutput omits usage when nil")
  func jsonOutputNilUsage() throws {
    let out = JSONOutput(content: "Hi", usage: nil)
    let dict = try json(out)
    #expect(dict["usage"] == nil)
  }

  // MARK: - RemoteEngine URL handling

  @Test("RemoteEngine normalizes host URL")
  func remoteBaseURL() throws {
    let engine = try RemoteEngine(host: "http://127.0.0.1:8888", token: nil)
    #expect(engine.base.absoluteString == "http://127.0.0.1:8888")
  }

  @Test("RemoteEngine rejects empty host")
  func remoteInvalidHost() {
    #expect(throws: OGError.usage("invalid host: ")) {
      try RemoteEngine(host: "", token: nil)
    }
  }

  // MARK: - EngineFactory dispatching

  @Test("nil host → LocalEngine")
  func factoryLocal() throws {
    let engine = try EngineFactory.make(host: nil, token: nil)
    #expect(engine is LocalEngine)
  }

  @Test("empty host → LocalEngine (guards against env=\"\")")
  func factoryEmptyHostIsLocal() throws {
    let engine = try EngineFactory.make(host: "", token: nil)
    #expect(engine is LocalEngine)
  }

  @Test("non-empty host → RemoteEngine")
  func factoryRemote() throws {
    let engine = try EngineFactory.make(host: "http://127.0.0.1:8888", token: "tok")
    #expect(engine is RemoteEngine)
  }
}
