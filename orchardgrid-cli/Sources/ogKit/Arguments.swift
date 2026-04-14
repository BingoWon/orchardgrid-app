import Foundation

// MARK: - Parsed Arguments

public struct Arguments: Sendable {
  public enum Mode: Sendable, Equatable {
    // Inference / info
    case help, version, modelInfo, chat, run, benchmark
    // Local snapshot (App Group state + saved config)
    case status
    // MCP diagnostics (no model inference)
    case mcpList
    // Auth
    case login, logout
    // Management
    case me
    case keysList, keysCreate, keysDelete
    case devicesList
    case logsList
  }

  public var mode: Mode = .run
  public var prompt: String = ""
  public var filePaths: [String] = []
  public var systemPrompt: String? = nil
  public var systemFile: String? = nil
  public var outputFormat: OutputFormat = .plain
  public var quiet: Bool = false
  public var noColor: Bool = false
  public var temperature: Double? = nil
  public var maxTokens: Int? = nil
  public var seed: UInt64? = nil
  public var contextStrategy: String? = nil
  public var contextMaxTurns: Int? = nil
  public var permissive: Bool = false
  /// Remote endpoint. When nil, `LocalEngine` runs in-process. When set
  /// (via `--host` or `ORCHARDGRID_HOST`), `RemoteEngine` talks HTTP.
  public var host: String? = nil
  public var token: String? = nil

  // Subcommand-specific fields.
  public var keyName: String? = nil
  public var keyHint: String? = nil
  public var logRole: String? = nil
  public var logStatus: String? = nil
  public var logLimit: Int = 50
  public var logOffset: Int = 0
  /// `og logout --revoke`: delete the local config AND revoke the
  /// management-scope API key server-side.
  public var logoutRevoke: Bool = false

  // `og benchmark` options.
  public var benchRuns: Int? = nil
  public var benchPrompt: String? = nil

  // MCP servers supplied via repeated `--mcp <path>`.
  public var mcpPaths: [String] = []
  public var mcpTimeoutSeconds: Int = 5

  public init() {}
}

public enum OutputFormat: String, Sendable { case plain, json }

// MARK: - Parsing

public enum CLIError: Error, CustomStringConvertible, Equatable {
  case missingValue(String)
  case invalidValue(String, String)
  case unknownFlag(String)
  case unknownSubcommand(String)
  case missingArgument(String)

  public var description: String {
    switch self {
    case .missingValue(let flag): "\(flag) requires a value"
    case .invalidValue(let flag, let val): "invalid value for \(flag): \(val)"
    case .unknownFlag(let flag): "unknown flag: \(flag)"
    case .unknownSubcommand(let name): "unknown subcommand: \(name)"
    case .missingArgument(let what): "missing argument: \(what)"
    }
  }
}

/// Reserved subcommand words. If the first positional arg is one of these,
/// we dispatch to subcommand mode instead of treating it as prompt text.
private let subcommandWords: Set<String> = [
  "login", "logout", "me", "keys", "devices", "logs", "status", "benchmark", "mcp",
]

/// Parse command-line arguments with environment-variable fallback.
public func parseArguments(_ args: [String], env: [String: String]) throws -> Arguments {
  var result = Arguments()

  if let host = env["ORCHARDGRID_HOST"] { result.host = host }
  if let token = env["ORCHARDGRID_TOKEN"] { result.token = token }
  if env["NO_COLOR"] != nil { result.noColor = true }

  var positional: [String] = []
  var i = 0

  func nextValue(_ flag: String) throws -> String {
    guard i + 1 < args.count else { throw CLIError.missingValue(flag) }
    i += 1
    return args[i]
  }

  while i < args.count {
    let a = args[i]
    switch a {
    case "-h", "--help": result.mode = .help
    case "-v", "--version": result.mode = .version
    case "--model-info": result.mode = .modelInfo
    case "--chat": result.mode = .chat
    case "-f", "--file":
      result.filePaths.append(try nextValue(a))
    case "-s", "--system":
      result.systemPrompt = try nextValue(a)
    case "--system-file":
      result.systemFile = try nextValue(a)
    case "-o", "--output":
      let v = try nextValue(a)
      guard let format = OutputFormat(rawValue: v) else { throw CLIError.invalidValue(a, v) }
      result.outputFormat = format
    case "-q", "--quiet":
      result.quiet = true
    case "--no-color":
      result.noColor = true
    case "--temperature":
      let v = try nextValue(a)
      guard let d = Double(v) else { throw CLIError.invalidValue(a, v) }
      result.temperature = d
    case "--max-tokens":
      let v = try nextValue(a)
      guard let n = Int(v) else { throw CLIError.invalidValue(a, v) }
      result.maxTokens = n
    case "--seed":
      let v = try nextValue(a)
      guard let n = UInt64(v) else { throw CLIError.invalidValue(a, v) }
      result.seed = n
    case "--context-strategy":
      let v = try nextValue(a)
      guard ["newest-first", "oldest-first", "sliding-window", "strict", "summarize"].contains(v)
      else { throw CLIError.invalidValue(a, v) }
      result.contextStrategy = v
    case "--context-max-turns":
      let v = try nextValue(a)
      guard let n = Int(v) else { throw CLIError.invalidValue(a, v) }
      result.contextMaxTurns = n
    case "--permissive":
      result.permissive = true
    case "--host":
      result.host = try nextValue(a)
    case "--token":
      result.token = try nextValue(a)
    case "--role":
      result.logRole = try nextValue(a)
    case "--status":
      result.logStatus = try nextValue(a)
    case "--limit":
      let v = try nextValue(a)
      guard let n = Int(v) else { throw CLIError.invalidValue(a, v) }
      result.logLimit = n
    case "--offset":
      let v = try nextValue(a)
      guard let n = Int(v) else { throw CLIError.invalidValue(a, v) }
      result.logOffset = n
    case "--name":
      result.keyName = try nextValue(a)
    case "--revoke":
      result.logoutRevoke = true
    case "--runs":
      let v = try nextValue(a)
      guard let n = Int(v), n > 0 else { throw CLIError.invalidValue(a, v) }
      result.benchRuns = n
    case "--bench-prompt":
      result.benchPrompt = try nextValue(a)
    case "--mcp":
      result.mcpPaths.append(try nextValue(a))
    case "--mcp-timeout":
      let v = try nextValue(a)
      guard let n = Int(v), n > 0 else { throw CLIError.invalidValue(a, v) }
      result.mcpTimeoutSeconds = n
    default:
      if a.hasPrefix("-") { throw CLIError.unknownFlag(a) }
      positional.append(a)
    }
    i += 1
  }

  // Flag-driven modes win over subcommand dispatch (e.g. `og --chat` even if
  // there's a stray positional).
  switch result.mode {
  case .help, .version, .modelInfo, .chat: return result
  default: break
  }

  // Subcommand dispatch: first positional is a reserved word.
  if let first = positional.first, subcommandWords.contains(first) {
    let rest = Array(positional.dropFirst())
    try applySubcommand(name: first, rest: rest, into: &result)
    return result
  }

  // Fallback: positionals are prompt text.
  result.prompt = positional.joined(separator: " ")
  return result
}

private func applySubcommand(
  name: String,
  rest: [String],
  into result: inout Arguments
) throws {
  switch name {
  case "login": result.mode = .login
  case "logout": result.mode = .logout
  case "me": result.mode = .me
  case "status": result.mode = .status
  case "benchmark": result.mode = .benchmark
  case "mcp":
    switch rest.first {
    case "list":
      guard rest.count >= 2 else { throw CLIError.missingArgument("mcp server path") }
      result.mode = .mcpList
      result.mcpPaths = Array(rest.dropFirst())
    default:
      throw CLIError.unknownSubcommand("mcp \(rest.first ?? "")")
    }
  case "devices":
    guard rest.isEmpty || rest.first == "list" else {
      throw CLIError.unknownSubcommand("devices \(rest.first ?? "")")
    }
    result.mode = .devicesList
  case "logs":
    result.mode = .logsList
  case "keys":
    switch rest.first ?? "list" {
    case "list":
      result.mode = .keysList
    case "create":
      result.mode = .keysCreate
      if rest.count >= 2 { result.keyName = rest[1] }
    case "delete":
      guard rest.count >= 2 else { throw CLIError.missingArgument("key hint") }
      result.mode = .keysDelete
      result.keyHint = rest[1]
    default:
      throw CLIError.unknownSubcommand("keys \(rest.first ?? "")")
    }
  default:
    throw CLIError.unknownSubcommand(name)
  }
}
