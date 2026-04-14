import Foundation

/// The single error type crossing network, parse, and domain boundaries.
///
/// Use `APIError.classify(_:)` to normalize any thrown error into this type.
/// Use `localizedDescription` for user-facing text (conforms to `LocalizedError`).
enum APIError: Error, Sendable, Equatable {
  /// Server returned a non-2xx status. `message` is the server-provided error, if any.
  case http(status: Int, message: String?)

  /// Transport-layer failure (DNS, timeout, offline, TLS).
  case transport(URLError)

  /// Response body could not be decoded.
  case decoding(String)

  /// Domain-level failure produced by our own code (misconfiguration, port in use, etc.).
  case local(String)

  /// Task cancellation (user-initiated or caller cancelled). Never user-facing.
  case cancelled

  /// Map any error into an `APIError`. Returns the input unchanged if already typed.
  static func classify(_ error: any Error) -> APIError {
    switch error {
    case let apiError as APIError: apiError
    case is CancellationError: .cancelled
    case let urlError as URLError where urlError.code == .cancelled: .cancelled
    case let urlError as URLError: .transport(urlError)
    case let decodingError as DecodingError: .decoding(String(describing: decodingError))
    default: .local(error.localizedDescription)
    }
  }
}

extension APIError: LocalizedError {
  var errorDescription: String? {
    switch self {
    case .http(let status, let message):
      if let message, !message.isEmpty { return message }
      return String(localized: "Server returned HTTP \(status).")
    case .transport(let urlError):
      return urlError.localizedDescription
    case .decoding:
      return String(localized: "Could not parse server response.")
    case .local(let message):
      return message
    case .cancelled:
      return nil
    }
  }
}
