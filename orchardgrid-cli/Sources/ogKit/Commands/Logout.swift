import ArgumentParser

// MARK: - og logout [--revoke]

struct Logout: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Drop local creds; --revoke also kills the remote token."
  )

  @OptionGroup var format: FormatOptions

  @Flag(help: "Also revoke the API key server-side.")
  var revoke: Bool = false

  func run() async throws {
    format.applyColor()
    try await runLogout(revoke: revoke)
  }
}
