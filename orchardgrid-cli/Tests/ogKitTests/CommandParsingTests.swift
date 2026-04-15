import ArgumentParser
import Darwin
import Testing

@testable import ogKit

// MARK: - Command parsing (swift-argument-parser)
//
// Exercises the subcommand tree + option groups via `Og.parseAsRoot`.
// We assert on the concrete subcommand type + its fields; we do NOT
// invoke `run()` (that would hit the network / FoundationModels).

@Suite("Command parsing")
struct CommandParsingTests {

  // MARK: - Defaults & top-level flags

  @Test("bare `og` selects the Run default subcommand with empty prompt")
  func defaultRun() throws {
    let cmd = try Og.parseAsRoot([])
    let run = try #require(cmd as? Run)
    #expect(run.words.isEmpty)
  }

  @Test("positional args become Run.words")
  func positionalPrompt() throws {
    let cmd = try Og.parseAsRoot(["hello", "world"])
    let run = try #require(cmd as? Run)
    #expect(run.words == ["hello", "world"])
  }

  // MARK: - Inference options on Run

  @Test("-f accumulates repeatable file paths")
  func fileRepeatable() throws {
    let cmd = try Og.parseAsRoot(["-f", "a.txt", "--file", "b.txt", "-f", "c.txt", "hi"])
    let run = try #require(cmd as? Run)
    #expect(run.inference.file == ["a.txt", "b.txt", "c.txt"])
    #expect(run.words == ["hi"])
  }

  @Test("-s / --system set system prompt", arguments: ["-s", "--system"])
  func systemFlag(_ flag: String) throws {
    let cmd = try Og.parseAsRoot([flag, "be helpful"])
    let run = try #require(cmd as? Run)
    #expect(run.inference.system == "be helpful")
  }

  @Test("--system-file sets system-file path")
  func systemFile() throws {
    let cmd = try Og.parseAsRoot(["--system-file", "prompt.txt"])
    let run = try #require(cmd as? Run)
    #expect(run.inference.systemFile == "prompt.txt")
  }

  @Test("-o accepts plain / json", arguments: ["plain", "json"])
  func outputValid(_ fmt: String) throws {
    let cmd = try Og.parseAsRoot(["-o", fmt])
    let run = try #require(cmd as? Run)
    #expect(run.inference.format.output.rawValue == fmt)
  }

  @Test("-o rejects invalid values")
  func outputInvalid() {
    #expect(throws: (any Error).self) {
      _ = try Og.parseAsRoot(["-o", "yaml"])
    }
  }

  @Test("-q / --quiet set quiet", arguments: ["-q", "--quiet"])
  func quiet(_ flag: String) throws {
    let cmd = try Og.parseAsRoot([flag])
    let run = try #require(cmd as? Run)
    #expect(run.inference.format.quiet == true)
  }

  @Test("--no-color sets noColor")
  func noColor() throws {
    let cmd = try Og.parseAsRoot(["--no-color"])
    let run = try #require(cmd as? Run)
    #expect(run.inference.format.noColor == true)
  }

  @Test("--permissive sets permissive")
  func permissive() throws {
    let cmd = try Og.parseAsRoot(["--permissive"])
    let run = try #require(cmd as? Run)
    #expect(run.inference.permissive == true)
  }

  @Test("--temperature parses Double")
  func temperature() throws {
    let cmd = try Og.parseAsRoot(["--temperature", "0.7"])
    let run = try #require(cmd as? Run)
    #expect(run.inference.temperature == 0.7)
  }

  @Test("--temperature rejects non-numeric")
  func temperatureInvalid() {
    #expect(throws: (any Error).self) {
      _ = try Og.parseAsRoot(["--temperature", "hot"])
    }
  }

  @Test("--max-tokens parses Int")
  func maxTokens() throws {
    let cmd = try Og.parseAsRoot(["--max-tokens", "512"])
    let run = try #require(cmd as? Run)
    #expect(run.inference.maxTokens == 512)
  }

  @Test("--seed parses UInt64")
  func seed() throws {
    let cmd = try Og.parseAsRoot(["--seed", "42"])
    let run = try #require(cmd as? Run)
    #expect(run.inference.seed == 42)
  }

  @Test("--seed rejects negative (UInt64)")
  func seedNegative() {
    #expect(throws: (any Error).self) {
      _ = try Og.parseAsRoot(["--seed", "-1"])
    }
  }

  @Test(
    "--context-strategy accepts the five valid names",
    arguments: ["newest-first", "oldest-first", "sliding-window", "summarize", "strict"])
  func contextStrategy(_ value: String) throws {
    let cmd = try Og.parseAsRoot(["--context-strategy", value])
    let run = try #require(cmd as? Run)
    #expect(run.inference.contextStrategy?.rawValue == value)
  }

  @Test("--context-strategy rejects unknown")
  func contextStrategyInvalid() {
    #expect(throws: (any Error).self) {
      _ = try Og.parseAsRoot(["--context-strategy", "bogus"])
    }
  }

  @Test("--context-max-turns parses Int")
  func contextMaxTurns() throws {
    let cmd = try Og.parseAsRoot(["--context-max-turns", "10"])
    let run = try #require(cmd as? Run)
    #expect(run.inference.contextMaxTurns == 10)
  }

  @Test("--host sets remote endpoint")
  func host() throws {
    let cmd = try Og.parseAsRoot(["--host", "http://example:9000"])
    let run = try #require(cmd as? Run)
    #expect(run.inference.network.host == "http://example:9000")
  }

  @Test("--token sets bearer token")
  func token() throws {
    let cmd = try Og.parseAsRoot(["--token", "sek"])
    let run = try #require(cmd as? Run)
    #expect(run.inference.network.token == "sek")
  }

  @Test("unknown flag is rejected")
  func unknownFlag() {
    #expect(throws: (any Error).self) {
      _ = try Og.parseAsRoot(["--bogus"])
    }
  }

  // MARK: - Chat / model-info

  @Test("`og chat` dispatches to Chat")
  func chatDispatch() throws {
    let cmd = try Og.parseAsRoot(["chat"])
    _ = try #require(cmd as? Chat)
  }

  @Test("`og model-info` dispatches to ModelInfo")
  func modelInfoDispatch() throws {
    let cmd = try Og.parseAsRoot(["model-info"])
    _ = try #require(cmd as? ModelInfo)
  }

  // MARK: - Benchmark

  @Test("`og benchmark` defaults runs / prompt to nil")
  func benchmarkDefaults() throws {
    let cmd = try Og.parseAsRoot(["benchmark"])
    let bench = try #require(cmd as? Benchmark)
    #expect(bench.runs == nil)
    #expect(bench.benchPrompt == nil)
  }

  @Test("`og benchmark --runs 3 --bench-prompt hi`")
  func benchmarkFlags() throws {
    let cmd = try Og.parseAsRoot(["benchmark", "--runs", "3", "--bench-prompt", "hi"])
    let bench = try #require(cmd as? Benchmark)
    #expect(bench.runs == 3)
    #expect(bench.benchPrompt == "hi")
  }

  @Test("`og benchmark --runs 0` is rejected")
  func benchmarkRejectsZeroRuns() {
    #expect(throws: (any Error).self) {
      let cmd = try Og.parseAsRoot(["benchmark", "--runs", "0"])
      if let bench = cmd as? Benchmark {
        try bench.validate()
      }
    }
  }

  // MARK: - MCP

  @Test("--mcp appends repeatedly on Run")
  func mcpRepeatable() throws {
    let cmd = try Og.parseAsRoot(
      ["--mcp", "/tmp/a.py", "--mcp", "/tmp/b.py", "hi"])
    let run = try #require(cmd as? Run)
    #expect(run.inference.mcp.paths == ["/tmp/a.py", "/tmp/b.py"])
    #expect(run.words == ["hi"])
  }

  @Test("--mcp-timeout parses positive Int")
  func mcpTimeout() throws {
    let cmd = try Og.parseAsRoot(["--mcp-timeout", "30", "hi"])
    let run = try #require(cmd as? Run)
    #expect(run.inference.mcp.timeoutSeconds == 30)
  }

  @Test("--mcp-timeout zero fails validation")
  func mcpTimeoutZero() {
    #expect(throws: (any Error).self) {
      let cmd = try Og.parseAsRoot(["--mcp-timeout", "0"])
      if let run = cmd as? Run { try run.inference.mcp.validate() }
    }
  }

  @Test("`og mcp list <path>` dispatches to MCP.List with paths")
  func mcpList() throws {
    let cmd = try Og.parseAsRoot(["mcp", "list", "/tmp/calc.py"])
    let list = try #require(cmd as? MCP.List)
    #expect(list.paths == ["/tmp/calc.py"])
  }

  @Test("`og mcp list` with no path fails validation")
  func mcpListMissing() {
    #expect(throws: (any Error).self) {
      let cmd = try Og.parseAsRoot(["mcp", "list"])
      if let list = cmd as? MCP.List { try list.validate() }
    }
  }

  // MARK: - Auth / management

  @Test("`og login` dispatches to Login")
  func login() throws {
    _ = try #require(try Og.parseAsRoot(["login"]) as? Login)
  }

  @Test("`og logout` defaults revoke=false; `--revoke` flips it")
  func logoutRevoke() throws {
    let bare = try #require(try Og.parseAsRoot(["logout"]) as? Logout)
    #expect(bare.revoke == false)
    let revoked = try #require(try Og.parseAsRoot(["logout", "--revoke"]) as? Logout)
    #expect(revoked.revoke == true)
  }

  @Test("`og me` dispatches to MeCommand")
  func meCommand() throws {
    _ = try #require(try Og.parseAsRoot(["me"]) as? MeCommand)
  }

  @Test("`og devices` and `og devices list` both hit Devices.List")
  func devicesDefault() throws {
    _ = try #require(try Og.parseAsRoot(["devices"]) as? Devices.List)
    _ = try #require(try Og.parseAsRoot(["devices", "list"]) as? Devices.List)
  }

  @Test("`og keys` defaults to Keys.List")
  func keysDefault() throws {
    _ = try #require(try Og.parseAsRoot(["keys"]) as? Keys.List)
    _ = try #require(try Og.parseAsRoot(["keys", "list"]) as? Keys.List)
  }

  @Test("`og keys create` no name")
  func keysCreateBare() throws {
    let cmd = try #require(try Og.parseAsRoot(["keys", "create"]) as? Keys.Create)
    #expect(cmd.name == nil)
    #expect(cmd.positionalName == nil)
  }

  @Test("`og keys create my-bot` sets positional name")
  func keysCreatePositional() throws {
    let cmd = try #require(try Og.parseAsRoot(["keys", "create", "my-bot"]) as? Keys.Create)
    #expect(cmd.positionalName == "my-bot")
  }

  @Test("`og keys create --name my-bot` sets flag name")
  func keysCreateFlag() throws {
    let cmd = try #require(
      try Og.parseAsRoot(["keys", "create", "--name", "my-bot"]) as? Keys.Create)
    #expect(cmd.name == "my-bot")
  }

  @Test("`og keys delete sk-abc` sets hint")
  func keysDelete() throws {
    let cmd = try #require(
      try Og.parseAsRoot(["keys", "delete", "sk-abc"]) as? Keys.Delete)
    #expect(cmd.hint == "sk-abc")
  }

  @Test("`og keys delete` without hint is rejected")
  func keysDeleteMissingHint() {
    #expect(throws: (any Error).self) {
      _ = try Og.parseAsRoot(["keys", "delete"])
    }
  }

  @Test("`og logs` defaults: limit=50, offset=0")
  func logsDefaults() throws {
    let cmd = try #require(try Og.parseAsRoot(["logs"]) as? Logs)
    #expect(cmd.limit == 50)
    #expect(cmd.offset == 0)
    #expect(cmd.role == nil)
    #expect(cmd.status == nil)
  }

  @Test("`og logs --role self --status completed --limit 5`")
  func logsFlags() throws {
    let cmd = try #require(
      try Og.parseAsRoot(
        ["logs", "--role", "self", "--status", "completed", "--limit", "5"])
      as? Logs)
    #expect(cmd.role == "self")
    #expect(cmd.status == "completed")
    #expect(cmd.limit == 5)
  }

  @Test("`og status` dispatches to Status")
  func statusDispatch() throws {
    _ = try #require(try Og.parseAsRoot(["status"]) as? Status)
  }
}

// MARK: - Environment fallback

@Suite("Environment fallback", .serialized)
struct EnvironmentTests {

  @Test("ORCHARDGRID_HOST fills --host when absent")
  func envHost() throws {
    setenv("ORCHARDGRID_HOST", "http://env:8080", 1)
    defer { unsetenv("ORCHARDGRID_HOST") }
    let opts = try NetworkOptions.parse([])
    #expect(opts.resolved().host == "http://env:8080")
  }

  @Test("explicit --host wins over env")
  func explicitBeatsEnv() throws {
    setenv("ORCHARDGRID_HOST", "http://env:8080", 1)
    defer { unsetenv("ORCHARDGRID_HOST") }
    let opts = try NetworkOptions.parse(["--host", "http://explicit:9000"])
    #expect(opts.resolved().host == "http://explicit:9000")
  }

  @Test("ORCHARDGRID_TOKEN fills --token when absent")
  func envToken() throws {
    setenv("ORCHARDGRID_TOKEN", "envtok", 1)
    defer { unsetenv("ORCHARDGRID_TOKEN") }
    let opts = try NetworkOptions.parse([])
    #expect(opts.resolved().token == "envtok")
  }
}
