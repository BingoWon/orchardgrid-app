import Foundation
import OrchardGridCore
import os

// MARK: - `og benchmark` — user-facing throughput probe
//
// Runs a fixed prompt N times against whichever engine is active (local
// FoundationModels by default, RemoteEngine if `--host` is set) and reports
// time-to-first-token (TTFT), total latency, tokens/sec, and output token
// counts. Stats are min / median / p95 / max / mean.
//
// Defaults: 5 runs, a ~100-token paragraph-generation prompt, deterministic
// sampling (temperature 0, max_tokens 256) so cross-run comparisons are
// meaningful.

public struct BenchmarkStat: Codable, Sendable, Equatable {
  public let min: Double
  public let median: Double
  public let p95: Double
  public let max: Double
  public let mean: Double

  public init(min: Double, median: Double, p95: Double, max: Double, mean: Double) {
    self.min = min
    self.median = median
    self.p95 = p95
    self.max = max
    self.mean = mean
  }

  public static func of(_ values: [Double]) -> BenchmarkStat {
    let sorted = values.sorted()
    let n = sorted.count
    guard n > 0 else { return BenchmarkStat(min: 0, median: 0, p95: 0, max: 0, mean: 0) }
    func pct(_ p: Double) -> Double {
      let idx = Swift.max(0, Swift.min(n - 1, Int((Double(n) * p).rounded(.up)) - 1))
      return sorted[idx]
    }
    return BenchmarkStat(
      min: sorted.first ?? 0,
      median: pct(0.5),
      p95: pct(0.95),
      max: sorted.last ?? 0,
      mean: values.reduce(0, +) / Double(n)
    )
  }
}

public struct BenchmarkReport: Codable, Sendable {
  public let version: String
  public let source: String
  public let runs: Int
  public let prompt: String
  public let ttftMs: BenchmarkStat
  public let totalMs: BenchmarkStat
  public let tokensPerSec: BenchmarkStat
  public let outputTokens: BenchmarkStat
}

public func runBenchmark(engine: LLMEngine, args: Arguments) async throws {
  let prompt =
    args.benchPrompt
    ?? "Write a short paragraph about the Apple Silicon family of chips."
  let runs = args.benchRuns ?? 5

  let health = try await engine.health()
  guard health.available else { throw OGError.modelUnavailable(health.detail) }

  let sourceLabel: String =
    switch health.source {
    case .onDevice: "on-device · FoundationModels"
    case .remote(let url): url.absoluteString
    }

  let chrome = args.outputFormat == .plain && !args.quiet
  if chrome {
    print("\(styled(AppIdentity.cliName, .cyan, .bold)) v\(ogVersion) — benchmark")
    print("\(styled("├", .dim)) source:  \(sourceLabel)")
    print("\(styled("├", .dim)) runs:    \(runs)")
    let preview = prompt.count > 64 ? "\(prompt.prefix(64))…" : prompt
    print("\(styled("└", .dim)) prompt:  \(preview)")
    print("")
  }

  var ttfts: [Double] = []
  var totals: [Double] = []
  var rates: [Double] = []
  var tokens: [Double] = []
  // Default to deterministic sampling (temperature 0, max_tokens 256) so
  // runs are comparable. User overrides via --temperature / --max-tokens
  // win — document in --help.
  let options = ChatOptions(
    temperature: args.temperature ?? 0,
    maxTokens: args.maxTokens ?? 256
  )

  for i in 1...runs {
    if chrome { writeStdout("run \(i)/\(runs)… ") }
    let start = DispatchTime.now().uptimeNanoseconds
    let firstDelta = OSAllocatedUnfairLock<UInt64?>(initialState: nil)
    let result = try await engine.chat(
      messages: [ChatMessage(role: "user", content: prompt)],
      options: options,
      mcp: nil
    ) { _ in
      firstDelta.withLock { if $0 == nil { $0 = DispatchTime.now().uptimeNanoseconds } }
    }
    let end = DispatchTime.now().uptimeNanoseconds
    let ttft = Double((firstDelta.withLock { $0 } ?? end) - start) / 1_000_000
    let total = Double(end - start) / 1_000_000
    let out = Double(result.usage?.completionTokens ?? 0)
    let gen = Swift.max(1.0, total - ttft)
    let rate = out > 0 ? out / (gen / 1000.0) : 0
    ttfts.append(ttft)
    totals.append(total)
    rates.append(rate)
    tokens.append(out)
    if chrome {
      print(
        String(
          format: "ttft %.0f ms · total %.0f ms · %.1f tok/s · %.0f tok",
          ttft, total, rate, out))
    }
  }

  let report = BenchmarkReport(
    version: ogVersion,
    source: sourceLabel,
    runs: runs,
    prompt: prompt,
    ttftMs: .of(ttfts),
    totalMs: .of(totals),
    tokensPerSec: .of(rates),
    outputTokens: .of(tokens)
  )

  switch args.outputFormat {
  case .json:
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(report)
    print(String(decoding: data, as: UTF8.self))
  case .plain:
    print("")
    print(styled("Summary", .cyan, .bold))
    printStatRow("ttft", report.ttftMs, unit: "ms", decimals: 0)
    printStatRow("total", report.totalMs, unit: "ms", decimals: 0)
    printStatRow("throughput", report.tokensPerSec, unit: "tok/s", decimals: 2)
    printStatRow("output", report.outputTokens, unit: "tok", decimals: 0)
  }
}

private func printStatRow(_ label: String, _ s: BenchmarkStat, unit: String, decimals: Int) {
  let fmt = "%.\(decimals)f"
  let labelPad = label.padding(toLength: 12, withPad: " ", startingAt: 0)
  let line =
    "  \(labelPad)  "
    + "min \(String(format: fmt, s.min))  "
    + "med \(String(format: fmt, s.median))  "
    + "p95 \(String(format: fmt, s.p95))  "
    + "max \(String(format: fmt, s.max))  "
    + "mean \(String(format: fmt, s.mean))  \(unit)"
  print(line)
}
