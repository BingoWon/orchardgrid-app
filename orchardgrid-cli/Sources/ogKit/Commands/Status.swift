import ArgumentParser

// MARK: - og status

struct Status: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Show app state, CLI login, capabilities (no network calls)."
  )

  @OptionGroup var format: FormatOptions

  func run() async throws {
    format.applyColor()
    runStatus(config: ConfigStore.load())
  }
}
