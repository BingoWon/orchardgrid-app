import Testing

@testable import OrchardGridCore

private struct ArbitraryError: Error {}

@Suite("ModelIssue.classify")
struct ModelIssueTests {

  @Test("a non-GenerationError maps to .unknown")
  func nonGenerationError() {
    #expect(ModelIssue.classify(ArbitraryError()) == .unknown)
  }

  @Test("default isRetryable flags rate / concurrency / assets as transient")
  func retryabilityDefaults() {
    #expect(ModelIssue.rateLimited.isRetryable)
    #expect(ModelIssue.concurrentRequests.isRetryable)
    #expect(ModelIssue.assetsUnavailable.isRetryable)
  }

  @Test("guardrail / context / decoding / unsupported are NOT retryable")
  func nonRetryableCases() {
    #expect(!ModelIssue.guardrail.isRetryable)
    #expect(!ModelIssue.contextOverflow.isRetryable)
    #expect(!ModelIssue.decodingFailure.isRetryable)
    #expect(!ModelIssue.unsupportedGuide.isRetryable)
    #expect(!ModelIssue.unsupportedLanguage.isRetryable)
    #expect(!ModelIssue.unknown.isRetryable)
  }
}
