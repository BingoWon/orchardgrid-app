import Testing

@testable import ogKit

@Suite("Subcommand dispatch")
struct SubcommandTests {

  // MARK: - Auth

  @Test("`og login` → .login")
  func loginMode() throws {
    #expect(try parseArguments(["login"], env: [:]).mode == .login)
  }

  @Test("`og logout` → .logout, revoke=false by default")
  func logoutMode() throws {
    let args = try parseArguments(["logout"], env: [:])
    #expect(args.mode == .logout)
    #expect(args.logoutRevoke == false)
  }

  @Test("`og logout --revoke` → .logout with revoke=true")
  func logoutRevoke() throws {
    let args = try parseArguments(["logout", "--revoke"], env: [:])
    #expect(args.mode == .logout)
    #expect(args.logoutRevoke == true)
  }

  // MARK: - me / devices

  @Test("`og me` → .me")
  func meMode() throws {
    #expect(try parseArguments(["me"], env: [:]).mode == .me)
  }

  @Test("`og devices` → .devicesList")
  func devicesMode() throws {
    #expect(try parseArguments(["devices"], env: [:]).mode == .devicesList)
  }

  @Test("`og devices list` → .devicesList")
  func devicesListMode() throws {
    #expect(try parseArguments(["devices", "list"], env: [:]).mode == .devicesList)
  }

  @Test("`og devices <unknown>` throws")
  func devicesUnknown() {
    #expect(throws: CLIError.unknownSubcommand("devices bogus")) {
      try parseArguments(["devices", "bogus"], env: [:])
    }
  }

  // MARK: - keys

  @Test("`og keys` → .keysList (default)")
  func keysDefault() throws {
    #expect(try parseArguments(["keys"], env: [:]).mode == .keysList)
  }

  @Test("`og keys list` → .keysList")
  func keysList() throws {
    #expect(try parseArguments(["keys", "list"], env: [:]).mode == .keysList)
  }

  @Test("`og keys create` → .keysCreate, no name")
  func keysCreateBare() throws {
    let args = try parseArguments(["keys", "create"], env: [:])
    #expect(args.mode == .keysCreate)
    #expect(args.keyName == nil)
  }

  @Test("`og keys create my-bot` → .keysCreate with name")
  func keysCreatePositional() throws {
    let args = try parseArguments(["keys", "create", "my-bot"], env: [:])
    #expect(args.mode == .keysCreate)
    #expect(args.keyName == "my-bot")
  }

  @Test("`og keys create --name my-bot` → .keysCreate via flag")
  func keysCreateFlag() throws {
    let args = try parseArguments(
      ["keys", "create", "--name", "my-bot"], env: [:])
    #expect(args.mode == .keysCreate)
    #expect(args.keyName == "my-bot")
  }

  @Test("`og keys delete sk-abc` → .keysDelete + hint")
  func keysDelete() throws {
    let args = try parseArguments(["keys", "delete", "sk-abc"], env: [:])
    #expect(args.mode == .keysDelete)
    #expect(args.keyHint == "sk-abc")
  }

  @Test("`og keys delete` without hint throws missingArgument")
  func keysDeleteMissingHint() {
    #expect(throws: CLIError.missingArgument("key hint")) {
      try parseArguments(["keys", "delete"], env: [:])
    }
  }

  @Test("`og keys bogus` throws unknownSubcommand")
  func keysUnknown() {
    #expect(throws: CLIError.unknownSubcommand("keys bogus")) {
      try parseArguments(["keys", "bogus"], env: [:])
    }
  }

  // MARK: - logs

  @Test("`og logs` → .logsList with defaults (limit=50 offset=0)")
  func logsDefaults() throws {
    let args = try parseArguments(["logs"], env: [:])
    #expect(args.mode == .logsList)
    #expect(args.logLimit == 50)
    #expect(args.logOffset == 0)
    #expect(args.logRole == nil)
    #expect(args.logStatus == nil)
  }

  @Test("`og logs --role self --status completed --limit 5`")
  func logsFlags() throws {
    let args = try parseArguments(
      ["logs", "--role", "self", "--status", "completed", "--limit", "5"],
      env: [:])
    #expect(args.mode == .logsList)
    #expect(args.logRole == "self")
    #expect(args.logStatus == "completed")
    #expect(args.logLimit == 5)
  }

  // MARK: - benchmark

  @Test("`og benchmark` → .benchmark with default runs/prompt")
  func benchmarkDefaults() throws {
    let args = try parseArguments(["benchmark"], env: [:])
    #expect(args.mode == .benchmark)
    #expect(args.benchRuns == nil)
    #expect(args.benchPrompt == nil)
  }

  @Test("`og benchmark --runs 3 --bench-prompt hi` sets both fields")
  func benchmarkFlags() throws {
    let args = try parseArguments(
      ["benchmark", "--runs", "3", "--bench-prompt", "hi"], env: [:])
    #expect(args.mode == .benchmark)
    #expect(args.benchRuns == 3)
    #expect(args.benchPrompt == "hi")
  }

  @Test("`og benchmark --runs 0` is rejected")
  func benchmarkRejectsZeroRuns() {
    #expect(throws: CLIError.self) {
      _ = try parseArguments(["benchmark", "--runs", "0"], env: [:])
    }
  }

  // MARK: - flag vs subcommand priority

  @Test("`og --chat` ignores stray `login` positional")
  func flagModeWins() throws {
    let args = try parseArguments(["--chat"], env: [:])
    #expect(args.mode == .chat)
  }

  @Test("positional that doesn't match a subcommand becomes prompt")
  func positionalBecomesPrompt() throws {
    let args = try parseArguments(["hello", "world"], env: [:])
    #expect(args.mode == .run)
    #expect(args.prompt == "hello world")
  }
}
