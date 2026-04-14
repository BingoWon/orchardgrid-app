import ClerkKit
import Foundation

@MainActor
@Observable
final class AuthManager {
  var showAuthSheet = false

  var isAuthenticated: Bool { Clerk.shared.user != nil }
  var userId: String? { Clerk.shared.user?.id }

  private let api: APIClient

  init(api: APIClient) {
    self.api = api
  }

  func signOut() async {
    try? await Clerk.shared.auth.signOut()
  }

  func deleteAccount() async throws {
    try await api.delete("/account")
    await signOut()
    Logger.log(.auth, "Account deleted successfully")
  }
}
