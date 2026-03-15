import ClerkKit
import Foundation

@MainActor
@Observable
final class AuthManager {
  var showAuthSheet = false

  var isAuthenticated: Bool { Clerk.shared.user != nil }
  var userId: String? { Clerk.shared.user?.id }

  var onUserIDChanged: ((String) -> Void)?
  var onLogout: (() -> Void)?

  func getToken() async -> String? {
    try? await Clerk.shared.session?.getToken()
  }

  func signOut() async {
    try? await Clerk.shared.auth.signOut()
  }

  func deleteAccount() async throws {
    guard let token = await getToken() else { return }
    let url = URL(string: "\(Config.apiBaseURL)/account")!
    var request = URLRequest(url: url)
    request.httpMethod = "DELETE"
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    let (data, response) = try await Config.urlSession.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
      throw NSError(domain: String(data: data, encoding: .utf8) ?? "Unknown error", code: -1)
    }
    await signOut()
    Logger.log(.auth, "Account deleted successfully")
  }
}
