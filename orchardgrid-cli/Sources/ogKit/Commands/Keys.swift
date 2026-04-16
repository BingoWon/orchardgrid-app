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
      try await runKeysList(client: try network.makeCloudClient())
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
      try await runKeysCreate(client: try network.makeCloudClient(), name: name)
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
      try await runKeysDelete(client: try network.makeCloudClient(), hint: hint)
    }
  }
}
