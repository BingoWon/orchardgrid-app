import Testing

@testable import OrchardGridCore

private struct Transient: Error {}
private struct Fatal: Error {}

/// Actor-wrapped counter so test operation closures can mutate shared
/// state safely under Swift 6 strict concurrency.
private actor Counter {
  private var n = 0
  func bump() -> Int {
    n += 1
    return n
  }
  func value() -> Int { n }
}

@Suite("Retry.withRetry")
struct RetryTests {

  @Test("returns immediately on first success")
  func firstTry() async throws {
    let counter = Counter()
    let result = try await Retry.withRetry(
      maxAttempts: 3, delays: [0, 0, 0],
      isRetryable: { _ in true }
    ) {
      _ = await counter.bump()
      return 42
    }
    #expect(result == 42)
    #expect(await counter.value() == 1)
  }

  @Test("retries a retryable error up to maxAttempts")
  func exhaustsAttempts() async {
    let counter = Counter()
    await #expect(throws: Transient.self) {
      try await Retry.withRetry(
        maxAttempts: 3, delays: [0, 0, 0],
        isRetryable: { _ in true }
      ) {
        _ = await counter.bump()
        throw Transient()
      }
    }
    #expect(await counter.value() == 3)
  }

  @Test("stops immediately on a non-retryable error")
  func nonRetryableBailsOut() async {
    let counter = Counter()
    await #expect(throws: Fatal.self) {
      try await Retry.withRetry(
        maxAttempts: 5, delays: [0, 0, 0, 0, 0],
        isRetryable: { !($0 is Fatal) }
      ) {
        _ = await counter.bump()
        throw Fatal()
      }
    }
    #expect(await counter.value() == 1)
  }

  @Test("recovers when an early attempt fails and a later one succeeds")
  func eventuallySucceeds() async throws {
    let counter = Counter()
    let result = try await Retry.withRetry(
      maxAttempts: 5, delays: [0, 0, 0, 0, 0],
      isRetryable: { _ in true }
    ) {
      let attempt = await counter.bump()
      if attempt < 3 { throw Transient() }
      return "ok"
    }
    #expect(result == "ok")
    #expect(await counter.value() == 3)
  }
}
