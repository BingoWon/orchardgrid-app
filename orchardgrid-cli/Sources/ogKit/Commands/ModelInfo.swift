import ArgumentParser

// MARK: - og model-info

struct ModelInfo: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "model-info",
    abstract: "Print model availability, source, and context window."
  )

  @OptionGroup var network: NetworkOptions
  @OptionGroup var format: FormatOptions

  func run() async throws {
    format.applyColor()
    let (host, token) = network.resolved()
    let engine = try EngineFactory.make(host: host, token: token)
    try await withOGErrorHandling {
      try await runModelInfo(engine: engine)
    }
  }
}
