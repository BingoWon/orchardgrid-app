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
    try await runMe(client: try network.makeCloudClient())
  }
}
