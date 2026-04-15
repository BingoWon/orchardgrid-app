import ArgumentParser

// MARK: - og benchmark

struct Benchmark: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Measure TTFT, total latency, throughput, and tokens/run."
  )

  @OptionGroup var inference: InferenceOptions

  @Option(help: "Number of benchmark runs.")
  var runs: Int?

  @Option(name: .customLong("bench-prompt"), help: "Override the default prompt.")
  var benchPrompt: String?

  func validate() throws {
    if let runs, runs <= 0 {
      throw ValidationError("--runs must be positive")
    }
  }

  func run() async throws {
    inference.format.applyColor()
    let (host, token) = inference.network.resolved()
    let engine = try EngineFactory.make(host: host, token: token)
    try await runBenchmark(
      engine: engine,
      prompt: benchPrompt,
      runs: runs,
      chatOptions: inference.chatOptions,
      outputFormat: inference.format.output,
      quiet: inference.format.quiet)
  }
}
