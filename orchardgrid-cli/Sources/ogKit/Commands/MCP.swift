import ArgumentParser

// MARK: - og mcp list <path>...

struct MCP: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "mcp",
    abstract: "Inspect Model Context Protocol servers.",
    subcommands: [List.self]
  )

  struct List: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Print the tool catalogue advertised by each server."
    )

    @OptionGroup var format: FormatOptions

    @Option(
      name: .customLong("mcp-timeout"),
      help: "Per-request MCP timeout in seconds.")
    var timeoutSeconds: Int = 5

    @Argument(help: "MCP server executable path(s).")
    var paths: [String] = []

    func validate() throws {
      if timeoutSeconds <= 0 {
        throw ValidationError("--mcp-timeout must be positive")
      }
      if paths.isEmpty {
        throw ValidationError("`og mcp list` requires at least one server path")
      }
    }

    func run() async throws {
      format.applyColor()
      try await runMCPList(
        paths: paths,
        timeoutSeconds: timeoutSeconds,
        outputFormat: format.output)
    }
  }
}
