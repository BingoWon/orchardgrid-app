@preconcurrency import FoundationModels

// MARK: - Error Classification (FoundationModels)

extension OGError {
  /// Classify a thrown error from FoundationModels into a semantic
  /// `OGError`. Keeps the exit-code mapping and user-facing wording
  /// in one place so callers just `throw OGError.fromGenerationError(error)`.
  static func fromGenerationError(_ error: Error) -> OGError {
    if let already = error as? OGError { return already }
    guard let gen = error as? LanguageModelSession.GenerationError else {
      return .runtime(error.localizedDescription)
    }
    return switch gen {
    case .exceededContextWindowSize: .contextOverflow("context window exceeded")
    case .guardrailViolation, .refusal: .guardrail("request blocked by safety guardrails")
    case .rateLimited: .rateLimited("rate limited — retry after a moment")
    case .concurrentRequests: .rateLimited("model busy with another request")
    case .assetsUnavailable: .modelUnavailable("model assets loading — try again")
    case .unsupportedGuide, .unsupportedLanguageOrLocale:
      .usage("unsupported generation guide or language")
    case .decodingFailure: .runtime("model output could not be decoded")
    @unknown default: .runtime(error.localizedDescription)
    }
  }
}
