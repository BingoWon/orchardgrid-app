import Foundation

// MARK: - Retry
//
// Shared exponential-backoff retry helper. Consumed by the CLI's
// RemoteEngine (transient network / HTTP 5xx) and the app's
// LLMProcessor (transient FoundationModels errors). Callers supply the
// retryability predicate — this module doesn't know anything about
// their error taxonomy.

public enum Retry {

  /// Default delays between retries: 0.1 s, 0.5 s, 2 s. Paired with
  /// `maxAttempts: 3` they give the caller one immediate retry plus
  /// two backed-off attempts, for four total tries of `operation`.
  public static let defaultDelays: [Double] = [0.1, 0.5, 2.0]

  /// Execute `operation` with up to `maxAttempts` total tries. On
  /// each caught error, consults `isRetryable` — if false, the error
  /// propagates immediately. Otherwise sleeps for `delays[attempt]`
  /// (clamped to the last delay once attempts > delays.count) and
  /// tries again. Returns the first successful result.
  public static func withRetry<T: Sendable>(
    maxAttempts: Int = 3,
    delays: [Double] = Retry.defaultDelays,
    isRetryable: @Sendable (Error) -> Bool,
    _ operation: @Sendable () async throws -> T
  ) async throws -> T {
    var attempt = 0
    while true {
      do {
        return try await operation()
      } catch {
        attempt += 1
        guard isRetryable(error), attempt < maxAttempts else { throw error }
        let delayIndex = min(attempt - 1, delays.count - 1)
        try? await Task.sleep(for: .seconds(delays[delayIndex]))
      }
    }
  }
}
