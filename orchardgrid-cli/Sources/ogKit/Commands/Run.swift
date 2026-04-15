import ArgumentParser
import Foundation

// MARK: - og run (default subcommand)

struct Run: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Send a single prompt (default action).",
    discussion: """
      Text is assembled from positional args, -f files, and piped stdin
      — in that priority. On-device by default; set --host to go remote.
      """
  )

  @OptionGroup var inference: InferenceOptions

  @Argument(help: "Prompt text.")
  var words: [String] = []

  func run() async throws {
    inference.format.applyColor()
    try inference.mcp.validate()

    let (host, token) = inference.network.resolved()
    let prompt = try assemblePrompt(
      positional: words.joined(separator: " "),
      filePaths: inference.file)
    guard !prompt.isEmpty else {
      throw CleanExit.helpRequest(Og.self)
    }

    let engine = try EngineFactory.make(host: host, token: token)
    try await withOGErrorHandling {
      try await withMCP(
        paths: inference.mcp.paths,
        timeoutSeconds: inference.mcp.timeoutSeconds,
        host: host,
        quiet: inference.format.quiet
      ) { mcp in
        try await runPrompt(
          engine: engine,
          prompt: prompt,
          systemPrompt: resolveSystemPrompt(
            system: inference.system, systemFile: inference.systemFile),
          chatOptions: inference.chatOptions,
          outputFormat: inference.format.output,
          mcp: mcp)
      }
    }
  }
}
