import Foundation

extension APIClient {
  /// A no-op client for SwiftUI previews. Never hits the network.
  static let preview = APIClient(
    baseURL: URL(string: "https://preview.invalid")!,
    tokenProvider: { nil }
  )
}
