import Foundation

// MARK: - Model Context Protocol — JSON-RPC 2.0 message formatting / parsing
//
// Pure wire-protocol helpers. No I/O, no subprocess management. Ported from
// the apfel reference and trimmed for og's needs (stdio transport only).
// See <https://spec.modelcontextprotocol.io> for the wire spec.

public enum MCPError: Error, Sendable, Equatable, CustomStringConvertible {
  case invalidResponse(String)
  case serverError(String)
  case toolNotFound(String)
  case processError(String)
  case timedOut(String)

  public var description: String {
    switch self {
    case .invalidResponse(let m), .serverError(let m), .toolNotFound(let m),
      .processError(let m), .timedOut(let m):
      return m
    }
  }
}

public struct MCPToolSchema: Sendable, Equatable {
  public let name: String
  public let description: String
  /// Raw JSON-Schema (OpenAPI-ish) describing the tool's input arguments.
  public let inputSchema: String

  public init(name: String, description: String, inputSchema: String) {
    self.name = name
    self.description = description
    self.inputSchema = inputSchema
  }
}

public enum MCPProtocol {
  public static let protocolVersion = "2025-06-18"

  // MARK: - Request framing

  public static func initializeRequest(
    id: Int,
    clientName: String,
    clientVersion: String
  ) -> String {
    jsonRPC(
      id: id, method: "initialize",
      params: [
        "protocolVersion": protocolVersion,
        "capabilities": [:] as [String: Any],
        "clientInfo": ["name": clientName, "version": clientVersion],
      ])
  }

  public static func initializedNotification() -> String {
    jsonRPC(method: "notifications/initialized")
  }

  public static func toolsListRequest(id: Int) -> String {
    jsonRPC(id: id, method: "tools/list")
  }

  public static func toolsCallRequest(id: Int, name: String, argumentsJSON: String) -> String {
    let argsObj = (try? JSONSerialization.jsonObject(with: Data(argumentsJSON.utf8))) ?? [:]
    return jsonRPC(
      id: id, method: "tools/call",
      params: ["name": name, "arguments": argsObj])
  }

  // MARK: - Response parsing

  public struct ServerInfo: Sendable, Equatable {
    public let name: String
    public let version: String
  }

  public static func parseInitializeResponse(_ json: String) throws -> ServerInfo {
    let obj = try parseJSON(json)
    guard let result = obj["result"] as? [String: Any],
      let info = result["serverInfo"] as? [String: Any]
    else {
      throw MCPError.invalidResponse("Missing serverInfo in initialize response")
    }
    return ServerInfo(
      name: info["name"] as? String ?? "unknown",
      version: info["version"] as? String ?? "unknown"
    )
  }

  public static func parseToolsListResponse(_ json: String) throws -> [MCPToolSchema] {
    let obj = try parseJSON(json)
    guard let result = obj["result"] as? [String: Any],
      let tools = result["tools"] as? [[String: Any]]
    else {
      throw MCPError.invalidResponse("Missing tools in tools/list response")
    }
    return tools.compactMap { tool -> MCPToolSchema? in
      guard let name = tool["name"] as? String else { return nil }
      let description = tool["description"] as? String ?? name
      let schemaJSON: String
      if let schema = tool["inputSchema"] as? [String: Any],
        let data = try? JSONSerialization.data(withJSONObject: schema),
        let str = String(data: data, encoding: .utf8)
      {
        schemaJSON = str
      } else {
        schemaJSON = #"{"type":"object","properties":{}}"#
      }
      return MCPToolSchema(name: name, description: description, inputSchema: schemaJSON)
    }
  }

  public struct ToolCallResult: Sendable, Equatable {
    public let text: String
    public let isError: Bool
  }

  public static func parseToolCallResponse(_ json: String) throws -> ToolCallResult {
    let obj = try parseJSON(json)
    if let error = obj["error"] as? [String: Any] {
      let message = error["message"] as? String ?? "Unknown MCP error"
      return ToolCallResult(text: message, isError: true)
    }
    guard let result = obj["result"] as? [String: Any],
      let content = result["content"] as? [[String: Any]],
      let first = content.first,
      let text = first["text"] as? String
    else {
      throw MCPError.invalidResponse("Missing content in tools/call response")
    }
    return ToolCallResult(text: text, isError: result["isError"] as? Bool ?? false)
  }

  // MARK: - Private

  private static func jsonRPC(
    id: Int? = nil, method: String, params: [String: Any]? = nil
  ) -> String {
    var msg: [String: Any] = ["jsonrpc": "2.0", "method": method]
    if let id { msg["id"] = id }
    if let params { msg["params"] = params }
    guard JSONSerialization.isValidJSONObject(msg),
      let data = try? JSONSerialization.data(withJSONObject: msg, options: [.sortedKeys]),
      let string = String(data: data, encoding: .utf8)
    else {
      let idFragment = id.map { #","id":\#($0)"# } ?? ""
      return #"{"jsonrpc":"2.0"\#(idFragment),"method":"\#(method)"}"#
    }
    return string
  }

  private static func parseJSON(_ s: String) throws -> [String: Any] {
    guard let data = s.data(using: .utf8),
      let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      throw MCPError.invalidResponse("Invalid JSON")
    }
    return obj
  }
}
