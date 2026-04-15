import ArgumentParser

// MARK: - og me

struct MeCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "me",
    abstract: "Print logged-in user info."
  )

  @OptionGroup var network: NetworkOptions
  @OptionGroup var format: FormatOptions

  func run() async throws {
    format.applyColor()
    let (host, token) = network.resolved()
    try await withOGErrorHandling {
      let client = try cloudClient(
        host: host, token: token, config: ConfigStore.load())
      try await runMe(client: client)
    }
  }
}
