import ArgumentParser
import Foundation
import OrchardGridCore

// MARK: - MCP lifecycle
//
// Spin up MCP servers for the duration of `body`, always shutting them
// down afterwards. Refuses `--mcp` with `--host` (MCP tool calling
// requires on-device inference). MCPError thrown by MCPManager setup
// is translated to OGError.runtime so the top-level handler in
// OgMain sees a single error taxonomy.

public func withMCP<T>(
  paths: [String],
  timeoutSeconds: Int,
  host: String?,
  quiet: Bool,
  _ body: (MCPManager?) async throws -> T
) async throws -> T {
  guard !paths.isEmpty else { return try await body(nil) }
  if host != nil {
    throw OGError.usage("--mcp requires on-device inference; remove --host to run locally")
  }
  let mcp: MCPManager
  do {
    mcp = try await MCPManager(
      paths: paths, timeoutSeconds: timeoutSeconds, logHeader: !quiet)
  } catch let err as MCPError {
    throw OGError.runtime("mcp error: \(err)")
  }
  do {
    let result = try await body(mcp)
    await mcp.shutdown()
    return result
  } catch {
    await mcp.shutdown()
    throw error
  }
}
