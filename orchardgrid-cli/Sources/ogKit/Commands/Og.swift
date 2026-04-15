import ArgumentParser
import OrchardGridCore

// MARK: - Root command
//
// Uses swift-argument-parser. Subcommand tree is the single source of
// truth for CLI behaviour; there is no hand-rolled dispatcher. `Run`
// is the default subcommand so `og "hello"` still sends a prompt
// without requiring `og run "hello"`.

public struct Og: AsyncParsableCommand {
  public static let configuration = CommandConfiguration(
    commandName: "og",
    abstract: "OrchardGrid CLI for Apple Foundation Model.",
    discussion: """
      Run inference on-device by default; set --host to target a peer or
      the OrchardGrid cloud. Sign in with `og login` to manage API keys,
      devices, and usage logs.
      """,
    version: "og v\(ogVersion) (\(ogBuildCommit), \(ogBuildDate))",
    subcommands: [
      Run.self,
      Chat.self,
      ModelInfo.self,
      Benchmark.self,
      MCP.self,
      Status.self,
      Login.self,
      Logout.self,
      Me.self,
      Keys.self,
      Devices.self,
      Logs.self,
    ],
    defaultSubcommand: Run.self
  )

  public init() {}
}
