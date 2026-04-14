import Foundation
@preconcurrency import FoundationModels

// MARK: - Model Context Protocol — stdio transport + tool registry
//
// `MCPConnection` owns one MCP server subprocess and serialises one
// request/response turn at a time over its stdio pipes. `MCPManager`
// aggregates multiple servers and routes tool calls by name. `MCPTool`
// bridges a discovered MCP tool schema into FoundationModels' native
// `Tool` protocol so `LanguageModelSession` can dispatch calls natively.

// MARK: - Subprocess connection

final class MCPConnection: @unchecked Sendable {
  let path: String
  private(set) var tools: [MCPToolSchema] = []

  private let timeoutMs: Int
  private let process: Process
  private let stdinPipe: Pipe
  private let stdoutPipe: Pipe
  private let reader: MCPLineReader
  private let lock = NSLock()
  private var nextId = 1

  init(path: String, timeoutSeconds: Int = 5) throws {
    let absolute = URL(fileURLWithPath: path).standardizedFileURL.path
    guard FileManager.default.fileExists(atPath: absolute) else {
      throw MCPError.processError("MCP server not found: \(absolute)")
    }
    self.path = absolute
    self.timeoutMs = timeoutSeconds * 1000

    let proc = Process()
    let stdin = Pipe()
    let stdout = Pipe()
    if absolute.hasSuffix(".py") {
      proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
      proc.arguments = ["python3", absolute]
    } else {
      proc.executableURL = URL(fileURLWithPath: absolute)
    }
    proc.standardInput = stdin
    proc.standardOutput = stdout
    proc.standardError = FileHandle.nullDevice
    self.process = proc
    self.stdinPipe = stdin
    self.stdoutPipe = stdout
    self.reader = MCPLineReader(fileDescriptor: stdout.fileHandleForReading.fileDescriptor)

    try proc.run()
    do {
      _ = try MCPProtocol.parseInitializeResponse(
        try roundtrip(MCPProtocol.initializeRequest(id: allocId()), label: "initialize"))
      send(MCPProtocol.initializedNotification())
      self.tools = try MCPProtocol.parseToolsListResponse(
        try roundtrip(MCPProtocol.toolsListRequest(id: allocId()), label: "tools/list"))
    } catch {
      if proc.isRunning { proc.terminate() }
      throw error
    }
  }

  func callTool(name: String, argumentsJSON: String) throws -> String {
    let raw: String
    do {
      raw = try roundtrip(
        MCPProtocol.toolsCallRequest(id: allocId(), name: name, argumentsJSON: argumentsJSON),
        label: "tool '\(name)'")
    } catch let err as MCPError {
      if case .timedOut = err { shutdown() }
      throw err
    }
    let result = try MCPProtocol.parseToolCallResponse(raw)
    if result.isError {
      throw MCPError.serverError("Tool '\(name)' failed: \(result.text)")
    }
    return result.text
  }

  func shutdown() { if process.isRunning { process.terminate() } }
  deinit { shutdown() }

  // MARK: - Private

  private func allocId() -> Int {
    lock.lock()
    defer { lock.unlock() }
    let id = nextId
    nextId += 1
    return id
  }

  private func send(_ message: String) {
    guard let data = (message + "\n").data(using: .utf8) else { return }
    stdinPipe.fileHandleForWriting.write(data)
  }

  private func roundtrip(_ message: String, label: String) throws -> String {
    send(message)
    return try reader.readLine(timeoutMilliseconds: timeoutMs, label: label)
  }
}

// MARK: - Manager (routes tool calls across servers)

public actor MCPManager {
  /// FoundationModels tool instances bound to this manager. Internal: the
  /// only consumer is `LocalEngine` inside the same module.
  private(set) var tools: [MCPTool] = []
  /// Public catalogue of server-advertised tool metadata.
  public private(set) var schemas: [MCPToolSchema] = []

  private var connections: [MCPConnection] = []
  private var toolMap: [String: MCPConnection] = [:]

  public init(paths: [String], timeoutSeconds: Int = 5, logHeader: Bool = true) async throws {
    for p in paths {
      let conn = try MCPConnection(path: p, timeoutSeconds: timeoutSeconds)
      connections.append(conn)
      for tool in conn.tools { toolMap[tool.name] = conn }
      if logHeader {
        let names = conn.tools.map(\.name).joined(separator: ", ")
        printErr("mcp: \(conn.path) — \(names.isEmpty ? "(no tools)" : names)")
      }
    }
    schemas = connections.flatMap(\.tools)
    tools = schemas.compactMap { try? MCPTool(schema: $0, manager: self) }
  }

  public func execute(name: String, argumentsJSON: String) async throws -> String {
    guard let conn = toolMap[name] else {
      throw MCPError.toolNotFound("No MCP server provides tool '\(name)'")
    }
    return try await Task.detached {
      try conn.callTool(name: name, argumentsJSON: argumentsJSON)
    }.value
  }

  public func shutdown() {
    for c in connections { c.shutdown() }
    connections.removeAll()
    toolMap.removeAll()
    tools.removeAll()
    schemas.removeAll()
  }
}

// MARK: - MCPTool — bridges a discovered MCP tool into a native FM Tool

struct MCPTool: Tool {
  typealias Arguments = GeneratedContent
  typealias Output = String

  let name: String
  let description: String
  let parameters: GenerationSchema

  private let manager: MCPManager

  init(schema: MCPToolSchema, manager: MCPManager) throws {
    self.name = schema.name
    self.description = schema.description
    self.manager = manager
    let root = try Self.convertSchema(json: schema.inputSchema, rootName: schema.name)
    self.parameters = try GenerationSchema(root: root, dependencies: [])
  }

  func call(arguments: GeneratedContent) async throws -> String {
    try await manager.execute(name: name, argumentsJSON: arguments.jsonString)
  }

  // MARK: - JSON-Schema → DynamicGenerationSchema

  private static func convertSchema(json: String, rootName: String) throws
    -> DynamicGenerationSchema
  {
    guard let data = json.data(using: .utf8),
      let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      throw MCPError.invalidResponse("Invalid tool inputSchema JSON")
    }
    return try convertNode(obj, name: rootName)
  }

  private static func convertNode(_ schema: [String: Any], name: String) throws
    -> DynamicGenerationSchema
  {
    let type = schema["type"] as? String ?? "object"
    let description = schema["description"] as? String
    switch type {
    case "object":
      let properties = schema["properties"] as? [String: Any] ?? [:]
      let required = Set(schema["required"] as? [String] ?? [])
      let propList: [DynamicGenerationSchema.Property] = try properties.sorted {
        $0.key < $1.key
      }.compactMap { key, value in
        guard let sub = value as? [String: Any] else { return nil }
        let child = try convertNode(sub, name: key)
        return DynamicGenerationSchema.Property(
          name: key, description: sub["description"] as? String,
          schema: child, isOptional: !required.contains(key))
      }
      return DynamicGenerationSchema(name: name, description: description, properties: propList)
    case "string":
      if let choices = schema["enum"] as? [String], !choices.isEmpty {
        return DynamicGenerationSchema(name: name, description: description, anyOf: choices)
      }
      return DynamicGenerationSchema(type: String.self)
    case "integer":
      return DynamicGenerationSchema(type: Int.self)
    case "number":
      return DynamicGenerationSchema(type: Double.self)
    case "boolean":
      return DynamicGenerationSchema(type: Bool.self)
    case "array":
      guard let items = schema["items"] as? [String: Any] else {
        throw MCPError.invalidResponse("array schema missing items")
      }
      let itemDyn = try convertNode(items, name: "\(name)_item")
      return DynamicGenerationSchema(arrayOf: itemDyn)
    default:
      throw MCPError.invalidResponse("unsupported JSON Schema type: \(type)")
    }
  }
}
