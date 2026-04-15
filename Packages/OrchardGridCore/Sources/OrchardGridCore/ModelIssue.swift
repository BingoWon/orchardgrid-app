@preconcurrency import FoundationModels

// MARK: - ModelIssue
//
// Abstract classification of a FoundationModels generation error.
// The single source of truth for "what kind of problem did the model
// hit?" — consumed by both `OGError.fromGenerationError` (CLI → exit
// codes) and `LLMError.classify` (app → HTTP status codes). Each
// consumer maps `ModelIssue` onto its own error enum, so CLI and app
// don't need to duplicate the switch-on-GenerationError logic.

public enum ModelIssue: Sendable, Equatable {
  case contextOverflow
  case guardrail
  case rateLimited
  case concurrentRequests
  case assetsUnavailable
  case unsupportedGuide
  case unsupportedLanguage
  case decodingFailure
  /// Not a recognised `LanguageModelSession.GenerationError` — caller
  /// falls back to a generic "runtime error" with `error.localizedDescription`.
  case unknown
}

extension ModelIssue {
  /// Classify a thrown FoundationModels error into an abstract `ModelIssue`.
  /// Returns `.unknown` for anything that isn't a `GenerationError`.
  public static func classify(_ error: Error) -> ModelIssue {
    guard let gen = error as? LanguageModelSession.GenerationError else {
      return .unknown
    }
    return switch gen {
    case .exceededContextWindowSize: .contextOverflow
    case .guardrailViolation, .refusal: .guardrail
    case .rateLimited: .rateLimited
    case .concurrentRequests: .concurrentRequests
    case .assetsUnavailable: .assetsUnavailable
    case .unsupportedGuide: .unsupportedGuide
    case .unsupportedLanguageOrLocale: .unsupportedLanguage
    case .decodingFailure: .decodingFailure
    @unknown default: .unknown
    }
  }

  /// Default retryability — true for transient issues that typically
  /// resolve on a second attempt without user intervention. Consumers
  /// can override by implementing their own `isRetryable` on top of
  /// this enum.
  public var isRetryable: Bool {
    switch self {
    case .rateLimited, .concurrentRequests, .assetsUnavailable: true
    default: false
    }
  }
}
