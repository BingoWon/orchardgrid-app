import Foundation
import OrchardGridCore

// MARK: - OGError + ExitCode
//
// One CLI-wide error taxonomy. Network / HTTP errors hop in via
// `fromHTTP`; FoundationModels errors via `fromModelError` (in
// `OGError+Generation.swift`). Each case carries a fixed exit code so
// shells can branch on `og`'s status without parsing stderr.

public enum OGError: Error, Equatable {
  case usage(String)
  case runtime(String)
  case guardrail(String)
  case contextOverflow(String)
  case modelUnavailable(String)
  case rateLimited(String)
  case serverUnreachable

  public var label: String {
    switch self {
    case .usage: "[usage]"
    case .runtime: "[error]"
    case .guardrail: "[guardrail]"
    case .contextOverflow: "[context overflow]"
    case .modelUnavailable: "[model unavailable]"
    case .rateLimited: "[rate limited]"
    case .serverUnreachable: "[unreachable]"
    }
  }

  public var message: String {
    switch self {
    case .usage(let m), .runtime(let m), .guardrail(let m),
      .contextOverflow(let m), .modelUnavailable(let m), .rateLimited(let m):
      m
    case .serverUnreachable:
      "could not reach the remote host"
    }
  }

  public var exitCode: Int32 {
    switch self {
    case .usage: ExitCode.usage.rawValue
    case .guardrail: ExitCode.guardrail.rawValue
    case .contextOverflow: ExitCode.contextOverflow.rawValue
    case .modelUnavailable: ExitCode.modelUnavailable.rawValue
    case .rateLimited: ExitCode.rateLimited.rawValue
    case .runtime, .serverUnreachable: ExitCode.runtime.rawValue
    }
  }
}

public enum ExitCode: Int32, Sendable {
  case success = 0
  case runtime = 1
  case usage = 2
  case guardrail = 3
  case contextOverflow = 4
  case modelUnavailable = 5
  case rateLimited = 6
}

// MARK: - HTTP error mapping

extension OGError {
  /// Map an HTTP status + JSON envelope from an OrchardGrid-compatible
  /// server onto a typed OGError. Bodies that don't deserialise as the
  /// expected envelope fall back to a generic `runtime("HTTP <code>")`.
  public static func fromHTTP(status: Int, body: Data) -> OGError {
    struct Envelope: Decodable {
      let error: Info
      struct Info: Decodable {
        let message: String
        let type: String
      }
    }
    let envelope = try? JSONDecoder().decode(Envelope.self, from: body)
    let message = envelope?.error.message ?? "HTTP \(status)"
    let type = envelope?.error.type ?? ""
    switch (status, type) {
    case (400, "content_policy_violation"): return .guardrail(message)
    case (400, "context_length_exceeded"): return .contextOverflow(message)
    case (401, _):
      return .runtime("authentication failed — run `\(AppIdentity.cliName) login` to re-authenticate")
    case (403, _):
      return .runtime(
        "forbidden — your token lacks management scope; run `\(AppIdentity.cliName) login` to upgrade")
    case (429, _): return .rateLimited(message)
    case (503, _): return .modelUnavailable(message)
    default: return .runtime(message)
    }
  }
}
