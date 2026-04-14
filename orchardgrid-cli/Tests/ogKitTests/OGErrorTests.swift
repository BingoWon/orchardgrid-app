import Foundation
import Testing

@testable import ogKit

@Suite("OGError classification")
struct OGErrorTests {

  private func envelope(type: String, message: String) -> Data {
    let json = """
      {"error":{"type":"\(type)","message":"\(message)"}}
      """
    return Data(json.utf8)
  }

  // MARK: - HTTP → OGError mapping

  @Test("400 content_policy_violation → guardrail")
  func guardrail() {
    let body = envelope(type: "content_policy_violation", message: "blocked")
    #expect(OGError.fromHTTP(status: 400, body: body) == .guardrail("blocked"))
  }

  @Test("400 context_length_exceeded → contextOverflow")
  func contextOverflow() {
    let body = envelope(type: "context_length_exceeded", message: "too long")
    #expect(OGError.fromHTTP(status: 400, body: body) == .contextOverflow("too long"))
  }

  @Test("401 → runtime telling user to run og login")
  func unauthorized() {
    let body = envelope(type: "authentication_error", message: "nope")
    let err = OGError.fromHTTP(status: 401, body: body)
    guard case .runtime(let m) = err else {
      Issue.record("expected .runtime, got \(err)")
      return
    }
    #expect(m.contains("og login"))
  }

  @Test("403 → runtime telling user to get a management token")
  func forbidden() {
    let body = envelope(type: "permission_error", message: "nope")
    let err = OGError.fromHTTP(status: 403, body: body)
    guard case .runtime(let m) = err else {
      Issue.record("expected .runtime, got \(err)")
      return
    }
    #expect(m.contains("og login"))
    #expect(m.contains("management"))
  }

  @Test("429 → rateLimited")
  func rateLimited() {
    let body = envelope(type: "rate_limit_error", message: "slow down")
    #expect(OGError.fromHTTP(status: 429, body: body) == .rateLimited("slow down"))
  }

  @Test("503 → modelUnavailable")
  func modelUnavailable() {
    let body = envelope(type: "server_error", message: "offline")
    #expect(OGError.fromHTTP(status: 503, body: body) == .modelUnavailable("offline"))
  }

  @Test("500 → runtime with message")
  func serverError() {
    let body = envelope(type: "server_error", message: "boom")
    #expect(OGError.fromHTTP(status: 500, body: body) == .runtime("boom"))
  }

  @Test("400 with unknown type falls through to runtime")
  func badRequestUnknownType() {
    let body = envelope(type: "weird_error", message: "huh")
    #expect(OGError.fromHTTP(status: 400, body: body) == .runtime("huh"))
  }

  @Test("invalid JSON body yields HTTP status message")
  func invalidJSON() {
    let body = Data("not json at all".utf8)
    #expect(OGError.fromHTTP(status: 502, body: body) == .runtime("HTTP 502"))
  }

  @Test("empty body yields HTTP status message")
  func emptyBody() {
    #expect(OGError.fromHTTP(status: 418, body: Data()) == .runtime("HTTP 418"))
  }

  // MARK: - Exit codes

  @Test(
    "exit codes align with documented taxonomy",
    arguments: [
      (OGError.usage("x"), ExitCode.usage.rawValue),
      (OGError.runtime("x"), ExitCode.runtime.rawValue),
      (OGError.guardrail("x"), ExitCode.guardrail.rawValue),
      (OGError.contextOverflow("x"), ExitCode.contextOverflow.rawValue),
      (OGError.modelUnavailable("x"), ExitCode.modelUnavailable.rawValue),
      (OGError.rateLimited("x"), ExitCode.rateLimited.rawValue),
      (OGError.serverUnreachable, ExitCode.runtime.rawValue),
    ])
  func exitCodes(_ err: OGError, _ expected: Int32) {
    #expect(err.exitCode == expected)
  }

  @Test("ExitCode raw values are stable (0–6)")
  func exitCodeValues() {
    #expect(ExitCode.success.rawValue == 0)
    #expect(ExitCode.runtime.rawValue == 1)
    #expect(ExitCode.usage.rawValue == 2)
    #expect(ExitCode.guardrail.rawValue == 3)
    #expect(ExitCode.contextOverflow.rawValue == 4)
    #expect(ExitCode.modelUnavailable.rawValue == 5)
    #expect(ExitCode.rateLimited.rawValue == 6)
  }

  // MARK: - Labels + messages

  @Test("label is distinct per case")
  func labels() {
    let all: [OGError] = [
      .usage("x"), .runtime("x"), .guardrail("x"),
      .contextOverflow("x"), .modelUnavailable("x"),
      .rateLimited("x"), .serverUnreachable,
    ]
    let labels = Set(all.map(\.label))
    #expect(labels.count == all.count)
  }

  @Test("serverUnreachable message is descriptive")
  func unreachableMessage() {
    #expect(OGError.serverUnreachable.message.contains("reach"))
  }
}
