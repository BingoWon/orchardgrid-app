import Testing

@testable import ogKit

@Suite("Arguments parsing")
struct ArgumentsTests {

  // MARK: - Modes

  @Test("default mode is .run")
  func defaultMode() throws {
    let args = try parseArguments([], env: [:])
    #expect(args.mode == .run)
  }

  @Test("-h / --help set mode to .help", arguments: ["-h", "--help"])
  func helpFlag(_ flag: String) throws {
    let args = try parseArguments([flag], env: [:])
    #expect(args.mode == .help)
  }

  @Test("-v / --version set mode to .version", arguments: ["-v", "--version"])
  func versionFlag(_ flag: String) throws {
    let args = try parseArguments([flag], env: [:])
    #expect(args.mode == .version)
  }

  @Test("--chat sets mode to .chat")
  func chatFlag() throws {
    let args = try parseArguments(["--chat"], env: [:])
    #expect(args.mode == .chat)
  }

  @Test("--model-info sets mode to .modelInfo")
  func modelInfoFlag() throws {
    let args = try parseArguments(["--model-info"], env: [:])
    #expect(args.mode == .modelInfo)
  }

  // MARK: - Positional prompt

  @Test("single positional becomes prompt")
  func singlePositional() throws {
    let args = try parseArguments(["hello"], env: [:])
    #expect(args.prompt == "hello")
  }

  @Test("multiple positionals are space-joined")
  func multiplePositionals() throws {
    let args = try parseArguments(["hello", "world", "foo"], env: [:])
    #expect(args.prompt == "hello world foo")
  }

  // MARK: - File attachment

  @Test("-f / --file accumulates repeatable paths")
  func fileFlag() throws {
    let args = try parseArguments(
      ["-f", "a.txt", "--file", "b.txt", "-f", "c.txt"], env: [:])
    #expect(args.filePaths == ["a.txt", "b.txt", "c.txt"])
  }

  @Test("-f without value throws missingValue")
  func fileMissingValue() {
    #expect(throws: CLIError.missingValue("-f")) {
      try parseArguments(["-f"], env: [:])
    }
  }

  // MARK: - System prompt

  @Test("-s / --system sets systemPrompt", arguments: ["-s", "--system"])
  func systemFlag(_ flag: String) throws {
    let args = try parseArguments([flag, "be helpful"], env: [:])
    #expect(args.systemPrompt == "be helpful")
  }

  @Test("--system-file sets systemFile path")
  func systemFileFlag() throws {
    let args = try parseArguments(["--system-file", "prompt.txt"], env: [:])
    #expect(args.systemFile == "prompt.txt")
  }

  // MARK: - Output format

  @Test("-o / --output parses valid formats", arguments: ["plain", "json"])
  func outputValid(_ fmt: String) throws {
    let args = try parseArguments(["-o", fmt], env: [:])
    #expect(args.outputFormat.rawValue == fmt)
  }

  @Test("-o rejects invalid values")
  func outputInvalid() {
    #expect(throws: CLIError.invalidValue("-o", "yaml")) {
      try parseArguments(["-o", "yaml"], env: [:])
    }
  }

  // MARK: - Flags without values

  @Test("-q / --quiet sets quiet", arguments: ["-q", "--quiet"])
  func quietFlag(_ flag: String) throws {
    let args = try parseArguments([flag], env: [:])
    #expect(args.quiet == true)
  }

  @Test("--no-color sets noColor")
  func noColorFlag() throws {
    let args = try parseArguments(["--no-color"], env: [:])
    #expect(args.noColor == true)
  }

  @Test("--permissive sets permissive")
  func permissiveFlag() throws {
    let args = try parseArguments(["--permissive"], env: [:])
    #expect(args.permissive == true)
  }

  // MARK: - Numeric values

  @Test("--temperature parses valid Double")
  func temperatureValid() throws {
    let args = try parseArguments(["--temperature", "0.7"], env: [:])
    #expect(args.temperature == 0.7)
  }

  @Test("--temperature rejects non-numeric values")
  func temperatureInvalid() {
    #expect(throws: CLIError.invalidValue("--temperature", "hot")) {
      try parseArguments(["--temperature", "hot"], env: [:])
    }
  }

  @Test("--max-tokens parses valid Int")
  func maxTokensValid() throws {
    let args = try parseArguments(["--max-tokens", "512"], env: [:])
    #expect(args.maxTokens == 512)
  }

  @Test("--seed parses valid UInt64")
  func seedValid() throws {
    let args = try parseArguments(["--seed", "42"], env: [:])
    #expect(args.seed == 42)
  }

  @Test("--seed rejects negative numbers (UInt64)")
  func seedNegative() {
    #expect(throws: CLIError.invalidValue("--seed", "-1")) {
      try parseArguments(["--seed", "-1"], env: [:])
    }
  }

  // MARK: - Context options

  @Test("--context-strategy stores raw string")
  func contextStrategy() throws {
    let args = try parseArguments(["--context-strategy", "strict"], env: [:])
    #expect(args.contextStrategy == "strict")
  }

  @Test("--context-max-turns parses Int")
  func contextMaxTurns() throws {
    let args = try parseArguments(["--context-max-turns", "10"], env: [:])
    #expect(args.contextMaxTurns == 10)
  }

  // MARK: - Host / token

  @Test("host is nil by default (falls back to LocalEngine)")
  func hostDefaultsToNil() throws {
    let args = try parseArguments([], env: [:])
    #expect(args.host == nil)
  }

  @Test("--host sets remote endpoint")
  func hostFlag() throws {
    let args = try parseArguments(["--host", "http://example:9000"], env: [:])
    #expect(args.host == "http://example:9000")
  }

  @Test("--token sets bearer token")
  func tokenFlag() throws {
    let args = try parseArguments(["--token", "sek"], env: [:])
    #expect(args.token == "sek")
  }

  // MARK: - Environment fallback

  @Test("ORCHARDGRID_HOST env sets default host")
  func envHost() throws {
    let args = try parseArguments([], env: ["ORCHARDGRID_HOST": "http://env:8080"])
    #expect(args.host == "http://env:8080")
  }

  @Test("ORCHARDGRID_TOKEN env sets default token")
  func envToken() throws {
    let args = try parseArguments([], env: ["ORCHARDGRID_TOKEN": "envtok"])
    #expect(args.token == "envtok")
  }

  @Test("NO_COLOR env sets noColor")
  func envNoColor() throws {
    let args = try parseArguments([], env: ["NO_COLOR": "1"])
    #expect(args.noColor == true)
  }

  @Test("explicit --host beats env ORCHARDGRID_HOST")
  func explicitBeatsEnv() throws {
    let args = try parseArguments(
      ["--host", "http://cli:1234"], env: ["ORCHARDGRID_HOST": "http://env:8080"])
    #expect(args.host == "http://cli:1234")
  }

  // MARK: - Error conditions

  @Test("unknown flag throws unknownFlag")
  func unknownFlag() {
    #expect(throws: CLIError.unknownFlag("--bogus")) {
      try parseArguments(["--bogus"], env: [:])
    }
  }

  @Test("error message formatting")
  func errorMessages() {
    #expect(CLIError.missingValue("-f").description == "-f requires a value")
    #expect(CLIError.invalidValue("-o", "x").description == "invalid value for -o: x")
    #expect(CLIError.unknownFlag("--bad").description == "unknown flag: --bad")
  }
}
