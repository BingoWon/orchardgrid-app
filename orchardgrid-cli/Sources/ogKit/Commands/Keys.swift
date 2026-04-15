import ArgumentParser

// MARK: - og keys list|create|delete

struct Keys: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Manage API keys.",
    subcommands: [List.self, Create.self, Delete.self],
    defaultSubcommand: List.self
  )

  // MARK: list

  struct List: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "List API keys on your account."
    )
    @OptionGroup var network: NetworkOptions
    @OptionGroup var format: FormatOptions

    func run() async throws {
      format.applyColor()
      let (host, token) = network.resolved()
      let client = try cloudClient(
        host: host, token: token, config: ConfigStore.load())
      try await runKeysList(client: client)
    }
  }

  // MARK: create

  struct Create: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Create a new inference-scope API key."
    )
    @OptionGroup var network: NetworkOptions
    @OptionGroup var format: FormatOptions

    @Argument(help: "Human-readable name for the key.")
    var name: String?

    func run() async throws {
      format.applyColor()
      let (host, token) = network.resolved()
      let client = try cloudClient(
        host: host, token: token, config: ConfigStore.load())
      try await runKeysCreate(client: client, name: name)
    }
  }

  // MARK: delete

  struct Delete: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Revoke an API key by hint prefix."
    )
    @OptionGroup var network: NetworkOptions
    @OptionGroup var format: FormatOptions

    @Argument(help: "Key hint (prefix) shown by `og keys list`.")
    var hint: String

    func run() async throws {
      format.applyColor()
      let (host, token) = network.resolved()
      let client = try cloudClient(
        host: host, token: token, config: ConfigStore.load())
      try await runKeysDelete(client: client, hint: hint)
    }
  }
}
