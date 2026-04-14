import Testing

@testable import ogKit

@Suite("ANSI styling")
struct OutputTests {

  @Test("disabled returns the text unchanged")
  func disabled() {
    let out = ANSI.apply("hello", styles: [.bold, .cyan], enabled: false)
    #expect(out == "hello")
  }

  @Test("enabled wraps with style prefixes and a reset")
  func enabled() {
    let out = ANSI.apply("hello", styles: [.bold, .cyan], enabled: true)
    #expect(out == "\u{001B}[1m\u{001B}[36mhello\u{001B}[0m")
  }

  @Test("no styles with enabled=true just wraps with reset (pure passthrough)")
  func noStyles() {
    let out = ANSI.apply("hello", styles: [], enabled: true)
    #expect(out == "hello\u{001B}[0m")
  }

  @Test("each Style has its own ANSI escape")
  func distinctEscapes() {
    let rawValues = Set(Style.allLike.map(\.rawValue))
    #expect(rawValues.count == Style.allLike.count)
  }
}

extension Style {
  /// Manual enumeration because `Style` isn't `CaseIterable` (no need in prod).
  fileprivate static let allLike: [Style] = [
    .bold, .dim, .cyan, .magenta, .green, .yellow, .red,
  ]
}
