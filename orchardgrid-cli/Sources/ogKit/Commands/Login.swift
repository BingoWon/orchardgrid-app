import ArgumentParser

// MARK: - og login

struct Login: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Open a browser, authorise this CLI, save the token."
  )

  @OptionGroup var network: NetworkOptions
  @OptionGroup var format: FormatOptions

  func run() async throws {
    format.applyColor()
    let (host, _) = network.resolved()
    try await runLogin(host: host)
  }
}
