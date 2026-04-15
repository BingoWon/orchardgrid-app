import Testing

@testable import ogKit

@Suite("MCP argument parsing")
struct MCPArgumentTests {

  @Test("--mcp appends repeatedly")
  func mcpRepeatable() throws {
    let args = try parseArguments(
      ["--mcp", "/tmp/a.py", "--mcp", "/tmp/b.py", "hi"], env: [:])
    #expect(args.mcpPaths == ["/tmp/a.py", "/tmp/b.py"])
    #expect(args.prompt == "hi")
  }

  @Test("--mcp-timeout parses positive Int")
  func mcpTimeout() throws {
    let args = try parseArguments(["--mcp-timeout", "30", "hi"], env: [:])
    #expect(args.mcpTimeoutSeconds == 30)
  }

  @Test("--mcp-timeout rejects zero / negative")
  func mcpTimeoutInvalid() {
    #expect(throws: CLIError.self) {
      _ = try parseArguments(["--mcp-timeout", "0"], env: [:])
    }
  }

  @Test("`og mcp list <path>` → .mcpList with paths")
  func mcpList() throws {
    let args = try parseArguments(["mcp", "list", "/tmp/calc.py"], env: [:])
    #expect(args.mode == .mcpList)
    #expect(args.mcpPaths == ["/tmp/calc.py"])
  }

  @Test("`og mcp list` with no path is rejected")
  func mcpListMissing() {
    #expect(throws: CLIError.self) {
      _ = try parseArguments(["mcp", "list"], env: [:])
    }
  }

  @Test("`og mcp` with no verb is rejected with a clean message")
  func mcpMissingVerb() {
    do {
      _ = try parseArguments(["mcp"], env: [:])
      Issue.record("expected throw")
    } catch let err as CLIError {
      let msg = err.description
      #expect(msg.contains("mcp verb"))
      #expect(!msg.hasSuffix(" "))
    } catch { Issue.record("wrong error: \(error)") }
  }

  @Test("`og mcp unknown` is rejected without trailing space")
  func mcpUnknownVerb() {
    do {
      _ = try parseArguments(["mcp", "wiggle"], env: [:])
      Issue.record("expected throw")
    } catch let err as CLIError {
      #expect(err.description == "unknown subcommand: mcp wiggle")
    } catch { Issue.record("wrong error: \(error)") }
  }

  @Test("--mcp combined with --host is rejected at parse time")
  func mcpAndHostMutuallyExclusive() {
    do {
      _ = try parseArguments(["--mcp", "/tmp/s.py", "--host", "http://x", "hi"], env: [:])
      Issue.record("expected throw")
    } catch let err as CLIError {
      #expect(err.description.contains("--mcp"))
      #expect(err.description.contains("on-device"))
    } catch { Issue.record("wrong error: \(error)") }
  }

  @Test("--mcp is allowed with `og mcp list` even if a host is in ORCHARDGRID_HOST")
  func mcpListIgnoresHostEnv() throws {
    let args = try parseArguments(
      ["mcp", "list", "/tmp/s.py"],
      env: ["ORCHARDGRID_HOST": "http://x"])
    #expect(args.mode == .mcpList)
  }
}
