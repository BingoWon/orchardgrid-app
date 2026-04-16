import ArgumentParser

// MARK: - og logs

struct Logs: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Browse usage logs."
  )

  @OptionGroup var network: NetworkOptions
  @OptionGroup var format: FormatOptions

  @Option(help: "Filter by role: consumer | provider | self.")
  var role: String?

  @Option(help: "Filter by status.")
  var status: String?

  @Option(help: "Page size.")
  var limit: Int = 50

  @Option(help: "Page offset.")
  var offset: Int = 0

  func run() async throws {
    format.applyColor()
    try await runLogsList(
      client: try network.makeCloudClient(),
      role: role, status: status, limit: limit, offset: offset)
  }
}
