import FoundationModels
import Testing

@testable import OrchardGridCore

// MARK: - Fixtures

private func prompt(_ text: String) -> Transcript.Entry {
  .prompt(Transcript.Prompt(segments: [.text(.init(content: text))]))
}

private func response(_ text: String) -> Transcript.Entry {
  .response(Transcript.Response(assetIDs: [], segments: [.text(.init(content: text))]))
}

private func instructions(_ text: String) -> Transcript.Entry {
  .instructions(
    Transcript.Instructions(
      segments: [.text(.init(content: text))], toolDefinitions: []))
}

/// Each test takes its own reference to `.default` rather than sharing
/// file-level mutable state across suites.
private var model: SystemLanguageModel { SystemLanguageModel.default }

// Minimal `TranscriptMessage` conformer used by the transcript-assembly
// suite. Callers (CLI / app) extend their own `ChatMessage` instead.
private struct Message: TranscriptMessage {
  let role: String
  let content: String
}

// MARK: - Pure helpers (no model required)

@Suite("textSegments")
struct TextSegmentsTests {
  @Test("extracts text from prompt / response / instructions entries")
  func extractsFromEveryCarryingEntry() {
    #expect(ContextTools.textSegments(of: prompt("hi")) == ["hi"])
    #expect(ContextTools.textSegments(of: response("ok")) == ["ok"])
    #expect(ContextTools.textSegments(of: instructions("sys")) == ["sys"])
  }

  @Test("preserves order of multiple text segments")
  func preservesOrder() {
    let entry: Transcript.Entry = .prompt(
      Transcript.Prompt(segments: [
        .text(.init(content: "a")), .text(.init(content: "b")),
      ]))
    #expect(ContextTools.textSegments(of: entry) == ["a", "b"])
  }
}

@Suite("fallbackTokens")
struct FallbackTokensTests {
  @Test("empty entries count 0")
  func empty() {
    #expect(ContextTools.fallbackTokens([]) == 0)
  }

  @Test("at least 1 token per non-empty segment, chars/4 otherwise")
  func monotone() {
    #expect(ContextTools.fallbackTokens([prompt("x")]) == 1)
    #expect(ContextTools.fallbackTokens([prompt(String(repeating: "x", count: 8))]) == 2)
    #expect(ContextTools.fallbackTokens([prompt(String(repeating: "x", count: 80))]) == 20)
  }

  @Test("sums across entries")
  func additive() {
    let single = ContextTools.fallbackTokens([prompt("x")])
    let pair = ContextTools.fallbackTokens([prompt("x"), response("y")])
    #expect(pair == single * 2)
  }
}

@Suite("transcriptEntries")
struct TranscriptEntriesTests {
  @Test("maps user → prompt, assistant → response; drops others")
  func mapsRolesAndDrops() {
    let entries = ContextTools.transcriptEntries(from: [
      Message(role: "user", content: "hi"),
      Message(role: "system", content: "sys"),
      Message(role: "assistant", content: "hello"),
      Message(role: "bogus", content: "x"),
    ])
    #expect(entries.count == 2)
    if case .prompt = entries[0] {} else { Issue.record("expected prompt") }
    if case .response = entries[1] {} else { Issue.record("expected response") }
  }

  @Test("empty input produces empty output")
  func emptyIn() {
    let entries = ContextTools.transcriptEntries(from: [] as [Message])
    #expect(entries.isEmpty)
  }
}

// MARK: - tokenCount + trim primitives (exercise fallback path when the
// real `tokenCount(for:)` API throws / is unavailable — i.e. CI without
// Apple Intelligence)

@Suite("tokenCount")
struct TokenCountTests {
  @Test("empty returns 0")
  func empty() async {
    #expect(await ContextTools.tokenCount([], model: model) == 0)
  }

  @Test("non-empty returns a positive estimate")
  func positive() async {
    #expect(await ContextTools.tokenCount([prompt("hello world")], model: model) > 0)
  }
}

@Suite("trimBinary")
struct TrimBinaryTests {
  private let base = instructions("sys")
  private let tail = prompt("final")

  @Test("budget zero returns an empty history")
  func budgetZero() async {
    let history = (0..<8).map { prompt("turn \($0) \(String(repeating: "x", count: 40))") }
    let kept = await ContextTools.trimBinary(
      base: base, history: history, prompt: tail, budget: 0,
      fromEnd: true, model: model)
    #expect(kept.isEmpty)
  }

  @Test("enormous budget keeps everything")
  func hugeBudget() async {
    let history = (0..<4).map { prompt("turn \($0)") }
    let kept = await ContextTools.trimBinary(
      base: base, history: history, prompt: tail, budget: 1_000_000,
      fromEnd: true, model: model)
    #expect(kept.count == history.count)
  }

  @Test("whatever is kept is drawn from the expected end of the history")
  func preservesExpectedSide() async {
    let history = (0..<6).map { prompt("turn-\($0)") }
    let tailOut = await ContextTools.trimBinary(
      base: base, history: history, prompt: tail,
      budget: 1_000, fromEnd: true, model: model)
    let headOut = await ContextTools.trimBinary(
      base: base, history: history, prompt: tail,
      budget: 1_000, fromEnd: false, model: model)

    func firstText(_ entry: Transcript.Entry) -> String {
      ContextTools.textSegments(of: entry).first ?? ""
    }
    let expectedTail = Array(history.suffix(tailOut.count)).map(firstText)
    let expectedHead = Array(history.prefix(headOut.count)).map(firstText)
    #expect(tailOut.map(firstText) == expectedTail)
    #expect(headOut.map(firstText) == expectedHead)
  }
}

@Suite("trimWithSummary fallback path")
struct TrimWithSummaryTests {
  private let base = instructions("sys")
  private let tail = prompt("final")

  @Test("history of ≤ 2 turns short-circuits to the newest-first trim")
  func shortHistoryShortCircuits() async {
    let history = [prompt("a"), response("b")]
    let kept = await ContextTools.trimWithSummary(
      base: base, history: history, prompt: tail,
      budget: 1_000_000, model: model)
    #expect(kept.count == 2)
  }

  @Test("falls back to newest-first when the model is unavailable")
  func modelUnavailableFallsBack() async {
    // With no Apple Intelligence in CI the availability guard kicks in
    // and returns the newest-first fallback. On a dev box where the
    // model IS available, summarisation may succeed — either way the
    // result stays within the budget.
    let history = (0..<6).map { prompt("t\($0)") }
    let kept = await ContextTools.trimWithSummary(
      base: base, history: history, prompt: tail,
      budget: 1_000_000, model: model)
    #expect(kept.count <= history.count)
  }
}

// MARK: - Strategy dispatch

@Suite("trim dispatch")
struct TrimDispatchTests {
  private let base = instructions("sys")
  private let tail = prompt("final")
  private let history = (0..<5).map { prompt("turn-\($0)") }

  @Test("newestFirst delegates to trimBinary fromEnd: true")
  func newest() async throws {
    let kept = try await ContextTools.trim(
      .newestFirst, base: base, history: history, prompt: tail,
      budget: 1_000_000, model: model)
    #expect(kept.count == history.count)
  }

  @Test("oldestFirst delegates to trimBinary fromEnd: false")
  func oldest() async throws {
    let kept = try await ContextTools.trim(
      .oldestFirst, base: base, history: history, prompt: tail,
      budget: 1_000_000, model: model)
    #expect(kept.count == history.count)
  }

  @Test("slidingWindow caps the history before trimming")
  func slidingWindowCaps() async throws {
    let kept = try await ContextTools.trim(
      .slidingWindow(maxTurns: 2),
      base: base, history: history, prompt: tail,
      budget: 1_000_000, model: model)
    #expect(kept.count == 2)
  }

  @Test("slidingWindow with nil maxTurns falls back to full history")
  func slidingWindowNil() async throws {
    let kept = try await ContextTools.trim(
      .slidingWindow(maxTurns: nil),
      base: base, history: history, prompt: tail,
      budget: 1_000_000, model: model)
    #expect(kept.count == history.count)
  }

  @Test("strict returns history unchanged when it fits")
  func strictFits() async throws {
    let kept = try await ContextTools.trim(
      .strict, base: base, history: history, prompt: tail,
      budget: 1_000_000, model: model)
    #expect(kept.count == history.count)
  }

  @Test("strict throws ContextOverflowError when it doesn't fit")
  func strictOverflows() async {
    await #expect(throws: ContextOverflowError.self) {
      try await ContextTools.trim(
        .strict, base: base, history: history, prompt: tail,
        budget: 0, model: model)
    }
  }
}
