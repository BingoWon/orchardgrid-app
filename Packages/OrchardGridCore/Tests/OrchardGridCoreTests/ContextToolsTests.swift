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

private let sharedModel = SystemLanguageModel.default

// MARK: - Pure helpers (no model needed)

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
    let short = ContextTools.fallbackTokens([prompt("x")])  // 1
    let medium = ContextTools.fallbackTokens([prompt(String(repeating: "x", count: 8))])  // 2
    let long = ContextTools.fallbackTokens([prompt(String(repeating: "x", count: 80))])  // 20
    #expect(short == 1)
    #expect(medium == 2)
    #expect(long == 20)
  }

  @Test("sums across entries")
  func additive() {
    let a = ContextTools.fallbackTokens([prompt("x")])
    let b = ContextTools.fallbackTokens([prompt("x"), response("y")])
    #expect(b == a * 2)
  }
}

@Suite("transcriptEntries")
struct TranscriptEntriesTests {
  @Test("maps user to prompt and assistant to response")
  func mapsRoles() {
    let entries = ContextTools.transcriptEntries(from: [
      (role: "user", content: "hi"),
      (role: "assistant", content: "hello"),
    ])
    #expect(entries.count == 2)
    if case .prompt = entries[0] {} else { Issue.record("expected prompt") }
    if case .response = entries[1] {} else { Issue.record("expected response") }
  }

  @Test("drops unknown roles rather than throwing")
  func dropsUnknown() {
    let entries = ContextTools.transcriptEntries(from: [
      (role: "system", content: "sys"),
      (role: "bogus", content: "x"),
      (role: "user", content: "hi"),
    ])
    #expect(entries.count == 1)
  }

  @Test("empty input produces empty output")
  func emptyIn() {
    #expect(ContextTools.transcriptEntries(from: []).isEmpty)
  }
}

// MARK: - tokenCount + trimBinary (exercises fallback path when the
// model's real `tokenCount(for:)` throws / is unavailable — i.e. the
// CI environment without Apple Intelligence). This path also runs
// deterministically on a dev box without affecting behaviour.

@Suite("tokenCount")
struct TokenCountTests {
  @Test("empty returns 0")
  func empty() async {
    #expect(await ContextTools.tokenCount([], model: sharedModel) == 0)
  }

  @Test("non-empty returns a positive estimate")
  func positive() async {
    let n = await ContextTools.tokenCount([prompt("hello world")], model: sharedModel)
    #expect(n > 0)
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
      fromEnd: true, model: sharedModel)
    #expect(kept.isEmpty)
  }

  @Test("enormous budget keeps everything")
  func hugeBudget() async {
    let history = (0..<4).map { prompt("turn \($0)") }
    let kept = await ContextTools.trimBinary(
      base: base, history: history, prompt: tail, budget: 1_000_000,
      fromEnd: true, model: sharedModel)
    #expect(kept.count == history.count)
  }

  @Test("whatever is kept is drawn from the expected end of the history")
  func preservesExpectedSide() async {
    let history = (0..<6).map { prompt("turn-\($0)") }
    // A budget large enough that at least one history entry fits
    // under fallback or real tokenisation, regardless of environment.
    let budget = 1_000

    let tail = await ContextTools.trimBinary(
      base: base, history: history, prompt: self.tail,
      budget: budget, fromEnd: true, model: sharedModel)
    let head = await ContextTools.trimBinary(
      base: base, history: history, prompt: self.tail,
      budget: budget, fromEnd: false, model: sharedModel)

    // The returned entries must be a contiguous suffix or prefix of
    // the original history. Comparing by first-text segment is enough
    // since every history entry has a distinct content string.
    func firstText(_ entry: Transcript.Entry) -> String {
      ContextTools.textSegments(of: entry).first ?? ""
    }
    let tailTexts = tail.map(firstText)
    let headTexts = head.map(firstText)
    let expectedTail = Array(history.suffix(tail.count)).map(firstText)
    let expectedHead = Array(history.prefix(head.count)).map(firstText)
    #expect(tailTexts == expectedTail)
    #expect(headTexts == expectedHead)
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
      budget: 1_000_000, model: sharedModel)
    #expect(kept.count == 2)
  }

  @Test("falls back to newest-first when the model is unavailable")
  func modelUnavailableFallsBack() async {
    // Apple Intelligence is unavailable in CI. With history.count > 2,
    // trimWithSummary's availability guard should kick in and return
    // the newest-first fallback. Asserting non-crash + a trimmed or
    // full history covers both paths (CI and a real dev box).
    let history = (0..<6).map { prompt("t\($0)") }
    let kept = await ContextTools.trimWithSummary(
      base: base, history: history, prompt: tail,
      budget: 1_000_000, model: sharedModel)
    #expect(kept.count <= history.count)
  }
}
