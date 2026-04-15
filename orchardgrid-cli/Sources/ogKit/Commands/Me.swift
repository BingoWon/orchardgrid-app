import ArgumentParser

// MARK: - og me

struct Me: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Print logged-in user info."
  )

  @OptionGroup var network: NetworkOptions
  @OptionGroup var format: FormatOptions

  func run() async throws {
    format.applyColor()
    let (host, token) = network.resolved()
    let client = try cloudClient(
      host: host, token: token, config: ConfigStore.load())
    try await runMe(client: client)
  }
}
