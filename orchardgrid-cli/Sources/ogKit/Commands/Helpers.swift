import ArgumentParser
import Foundation
import OrchardGridCore

// MARK: - Error bridging
//
// SAP expects commands to `throw ExitCode` (its own type, from
// ArgumentParser) for custom exit codes. OGError carries our taxonomy
// with label + message + integer exit code; we print the label/message
// to stderr and propagate via SAP's ExitCode so the top-level handler
// exits with the correct status.

/// Translate MCPError → OGError so everything flows through the same
/// single source of truth in `OgMain`, which prints the stderr line
/// and uses `OGError.exitCode`. Does not print here — that would
/// produce duplicate "[label] message" lines for OGError that was
/// thrown deeper (e.g. from `assemblePrompt`) and already propagates
/// straight to `OgMain`.
public func withOGErrorHandling<T>(
  _ body: () async throws -> T
) async throws -> T {
  do {
    return try await body()
  } catch let mcp as MCPError {
    throw OGError.runtime("mcp error: \(mcp)")
  }
}

// MARK: - MCP lifecycle

/// Spin up MCP servers for the duration of `body`, always shutting them
/// down afterwards. Refuses `--mcp` with `--host` at the boundary —
/// MCP tool calling requires on-device FoundationModels.
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
  let mcp = try await MCPManager(
    paths: paths, timeoutSeconds: timeoutSeconds, logHeader: !quiet)
  do {
    let result = try await body(mcp)
    await mcp.shutdown()
    return result
  } catch {
    await mcp.shutdown()
    throw error
  }
}
