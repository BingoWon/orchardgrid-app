import ArgumentParser
import Foundation
import OrchardGridCore

// MARK: - Output format

public enum OutputFormat: String, Sendable, ExpressibleByArgument, CaseIterable {
  case plain, json
}

// MARK: - Context strategy adapter
//
// `ContextStrategy` in OrchardGridCore carries an associated value
// (`.slidingWindow(maxTurns:)`), so it can't conform to
// `ExpressibleByArgument` directly. This wrapper enum exposes only
// the five wire identifiers SAP needs. `--context-max-turns` is a
// separate flag that the caller combines at dispatch time.

public enum ContextStrategyName: String, Sendable, ExpressibleByArgument, CaseIterable {
  case newestFirst = "newest-first"
  case oldestFirst = "oldest-first"
  case slidingWindow = "sliding-window"
  case summarize
  case strict

  public func toStrategy(maxTurns: Int?) -> ContextStrategy {
    ContextStrategy.parse(rawValue, maxTurns: maxTurns) ?? .newestFirst
  }
}

// MARK: - Option groups

/// Presentation flags shared by every command that produces output.
/// `noColor` also honours `NO_COLOR` env var at resolve time.
public struct FormatOptions: ParsableArguments {
  @Option(
    name: [.short, .long],
    help: "Output format.")
  public var output: OutputFormat = .plain

  @Flag(name: [.short, .long], help: "Suppress chrome (banners, progress).")
  public var quiet: Bool = false

  @Flag(name: .customLong("no-color"), help: "Disable ANSI color.")
  public var noColor: Bool = false

  public init() {}

  /// Install into the module-level `noColor` sink read by `ANSI.apply`.
  public func applyColor() {
    let envNoColor = ProcessInfo.processInfo.environment["NO_COLOR"] != nil
    ogKit.applyGlobalNoColor(noColor || envNoColor)
  }
}

/// Remote endpoint + auth — shared by inference (`--host` optional,
/// triggers `RemoteEngine`) and management (`--host` optional, defaults
/// to cloud). Env fallback resolved on read.
public struct NetworkOptions: ParsableArguments {
  @Option(help: "Remote OrchardGrid host. Env: ORCHARDGRID_HOST.")
  public var host: String?

  @Option(help: "Bearer token. Env: ORCHARDGRID_TOKEN.")
  public var token: String?

  public init() {}

  public func resolved() -> (host: String?, token: String?) {
    let env = ProcessInfo.processInfo.environment
    return (host ?? env["ORCHARDGRID_HOST"], token ?? env["ORCHARDGRID_TOKEN"])
  }
}

/// MCP servers attached to on-device inference. Repeating `--mcp` adds
/// paths; `--mcp-timeout` applies per request.
public struct MCPOptions: ParsableArguments {
  @Option(
    name: .customLong("mcp"),
    help: "Attach an MCP server (repeatable; on-device only).")
  public var paths: [String] = []

  @Option(
    name: .customLong("mcp-timeout"),
    help: "Per-request MCP timeout in seconds.")
  public var timeoutSeconds: Int = 5

  public init() {}

  public func validate() throws {
    if timeoutSeconds <= 0 {
      throw ValidationError("--mcp-timeout must be positive")
    }
  }
}

/// Everything inference commands (`run`, `chat`) need. `model-info` and
/// `benchmark` reuse `NetworkOptions` + `FormatOptions` without the
/// conversation-shaping knobs.
public struct InferenceOptions: ParsableArguments {
  @OptionGroup public var network: NetworkOptions
  @OptionGroup public var format: FormatOptions
  @OptionGroup public var mcp: MCPOptions

  @Option(
    name: [.short, .long],
    help: "Attach file content (repeatable).")
  public var file: [String] = []

  @Option(name: [.short, .long], help: "System prompt.")
  public var system: String?

  @Option(name: .customLong("system-file"), help: "System prompt from file.")
  public var systemFile: String?

  @Option(help: "Sampling temperature.")
  public var temperature: Double?

  @Option(name: .customLong("max-tokens"), help: "Max response tokens.")
  public var maxTokens: Int?

  @Option(help: "Random seed.")
  public var seed: UInt64?

  @Option(name: .customLong("context-strategy"), help: "How to fit history into the context window.")
  public var contextStrategy: ContextStrategyName?

  @Option(name: .customLong("context-max-turns"), help: "Max turns for sliding-window.")
  public var contextMaxTurns: Int?

  @Flag(help: "Permissive content guardrails.")
  public var permissive: Bool = false

  public init() {}

  public var chatOptions: ChatOptions {
    ChatOptions(
      temperature: temperature,
      maxTokens: maxTokens,
      seed: seed,
      contextStrategy: contextStrategy?.rawValue,
      contextMaxTurns: contextMaxTurns,
      permissive: permissive
    )
  }
}
