import Foundation
import OrchardGridCore

/// Semantic error type for on-device LLM operations.
/// The taxonomy decision (what GenerationError case maps to which
/// concept) lives in `OrchardGridCore.ModelIssue`; this enum adds the
/// HTTP-layer wrapping the API server needs.
enum LLMError: Error, Sendable {
  case modelUnavailable
  case invalidRequest(String)
  case guardrailViolation
  case contextOverflow
  case rateLimited
  case concurrentRequest
  case assetsUnavailable
  case generationFailed(String)

  /// Map any thrown error to a typed `LLMError`. Delegates the
  /// FoundationModels classification to `ModelIssue.classify`, so this
  /// and the CLI's `OGError.fromModelError` stay in lock-step.
  static func classify(_ error: Error) -> LLMError {
    if let already = error as? LLMError { return already }
    switch ModelIssue.classify(error) {
    case .contextOverflow: return .contextOverflow
    case .guardrail: return .guardrailViolation
    case .rateLimited: return .rateLimited
    case .concurrentRequests: return .concurrentRequest
    case .assetsUnavailable: return .assetsUnavailable
    case .unsupportedGuide: return .invalidRequest("Unsupported generation guide")
    case .unsupportedLanguage: return .invalidRequest("Unsupported language or locale")
    case .decodingFailure: return .generationFailed("Model output could not be decoded")
    case .unknown: return .generationFailed(error.localizedDescription)
    }
  }

  /// Whether the underlying condition is transient and worth retrying.
  var isRetryable: Bool {
    switch self {
    case .rateLimited, .concurrentRequest, .assetsUnavailable: true
    default: false
    }
  }

  var httpStatusCode: Int {
    switch self {
    case .invalidRequest, .guardrailViolation, .contextOverflow: 400
    case .rateLimited, .concurrentRequest: 429
    case .modelUnavailable, .assetsUnavailable: 503
    case .generationFailed: 500
    }
  }

  var openAIType: String {
    switch self {
    case .invalidRequest: "invalid_request_error"
    case .guardrailViolation: "content_policy_violation"
    case .contextOverflow: "context_length_exceeded"
    case .rateLimited, .concurrentRequest: "rate_limit_error"
    case .modelUnavailable, .assetsUnavailable, .generationFailed: "server_error"
    }
  }
}

extension LLMError: LocalizedError {
  var errorDescription: String? {
    switch self {
    case .modelUnavailable: "Model is not available"
    case .invalidRequest(let m): "Invalid request: \(m)"
    case .guardrailViolation: "Request blocked by safety guardrails"
    case .contextOverflow: "Input exceeds the context window"
    case .rateLimited: "Rate limited — retry after a moment"
    case .concurrentRequest: "Model busy — retry shortly"
    case .assetsUnavailable: "Model assets loading — try again"
    case .generationFailed(let m): m
    }
  }
}

// MARK: - HTTP status text

/// Standard reason phrase for an HTTP status code. Shared by `HTTPError` and
/// `LLMError` response paths so the mapping lives in exactly one place.
func httpStatusText(_ code: Int) -> String {
  switch code {
  case 200: "OK"
  case 204: "No Content"
  case 400: "Bad Request"
  case 401: "Unauthorized"
  case 404: "Not Found"
  case 429: "Too Many Requests"
  case 500: "Internal Server Error"
  case 503: "Service Unavailable"
  default: "Error"
  }
}
