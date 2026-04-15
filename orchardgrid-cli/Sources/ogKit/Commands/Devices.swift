import ArgumentParser

// MARK: - og devices [list]

struct Devices: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "List your registered devices.",
    subcommands: [List.self],
    defaultSubcommand: List.self
  )

  struct List: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Print online/offline status and platform for each device."
    )
    @OptionGroup var network: NetworkOptions
    @OptionGroup var format: FormatOptions

    func run() async throws {
      format.applyColor()
      let (host, token) = network.resolved()
      try await withOGErrorHandling {
        let client = try cloudClient(
          host: host, token: token, config: ConfigStore.load())
        try await runDevicesList(client: client)
      }
    }
  }
}
