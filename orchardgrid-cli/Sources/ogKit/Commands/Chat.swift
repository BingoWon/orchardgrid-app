import ArgumentParser

// MARK: - og chat

struct Chat: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Interactive REPL. Type 'quit' to exit."
  )

  @OptionGroup var inference: InferenceOptions

  func run() async throws {
    inference.format.applyColor()
    try inference.mcp.validate()

    let (host, token) = inference.network.resolved()
    let engine = try EngineFactory.make(host: host, token: token)

    try await withMCP(
      paths: inference.mcp.paths,
      timeoutSeconds: inference.mcp.timeoutSeconds,
      host: host,
      quiet: inference.format.quiet
    ) { mcp in
      try await runChat(
        engine: engine,
        systemPrompt: resolveSystemPrompt(
          system: inference.system, systemFile: inference.systemFile),
        chatOptions: inference.chatOptions,
        quiet: inference.format.quiet,
        mcp: mcp)
    }
  }
}
