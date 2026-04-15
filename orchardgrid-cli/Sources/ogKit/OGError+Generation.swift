import Foundation
import OrchardGridCore

// MARK: - Error Classification
//
// Two translation layers sit here:
//
//  1. `OGError.fromModelError(_:)` maps a FoundationModels-era thrown
//     error (or any OGError already in flight) onto a semantic OGError
//     with exit-code + user-facing wording. Delegates the taxonomy
//     decision to `OrchardGridCore.ModelIssue.classify`, so the CLI and
//     the app stay in lock-step on what "guardrail" / "rate limited" /
//     "context overflow" mean.
//
//  2. `OGError.isRetryable` makes OGError plug-compatible with
//     `OrchardGridCore.Retry.withRetry(isRetryable:)`.

extension OGError {
  static func fromModelError(_ error: Error) -> OGError {
    if let already = error as? OGError { return already }
    switch ModelIssue.classify(error) {
    case .contextOverflow: return .contextOverflow("context window exceeded")
    case .guardrail: return .guardrail("request blocked by safety guardrails")
    case .rateLimited: return .rateLimited("rate limited — retry after a moment")
    case .concurrentRequests: return .rateLimited("model busy with another request")
    case .assetsUnavailable: return .modelUnavailable("model assets loading — try again")
    case .unsupportedGuide, .unsupportedLanguage:
      return .usage("unsupported generation guide or language")
    case .decodingFailure: return .runtime("model output could not be decoded")
    case .unknown: return .runtime(error.localizedDescription)
    }
  }

  /// Whether this error should be retried by `Retry.withRetry`.
  var isRetryable: Bool {
    switch self {
    case .rateLimited: true
    default: false
    }
  }
}
