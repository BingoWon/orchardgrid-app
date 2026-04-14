import Foundation

// MARK: - `og mcp list <path> [<path>…]`
//
// Spins up each MCP server, prints the tool catalogue each one advertises,
// then shuts them down. Useful for verifying an MCP server works with og
// before plumbing it into a live inference call.

public func runMCPList(args: Arguments) async throws {
  guard !args.mcpPaths.isEmpty else {
    throw OGError.usage("`og mcp list` requires at least one server path")
  }
  let manager = try await MCPManager(
    paths: args.mcpPaths,
    timeoutSeconds: args.mcpTimeoutSeconds,
    logHeader: false
  )
  defer { Task { await manager.shutdown() } }

  let schemas = await manager.schemas
  switch args.outputFormat {
  case .json:
    struct Entry: Encodable {
      let name: String
      let description: String
      let inputSchema: String
    }
    let payload = schemas.map {
      Entry(name: $0.name, description: $0.description, inputSchema: $0.inputSchema)
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    print(String(decoding: try encoder.encode(payload), as: UTF8.self))
  case .plain:
    if schemas.isEmpty {
      print("No tools advertised.")
      return
    }
    print("\(styled("og", .cyan, .bold)) v\(ogVersion) — MCP tools")
    for schema in schemas {
      print("\(styled("•", .dim)) \(styled(schema.name, .cyan, .bold))")
      print("  \(styled("desc:", .dim)) \(schema.description)")
    }
  }
}
