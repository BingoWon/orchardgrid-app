import ClerkKit
import Foundation

@MainActor
@Observable
final class AuthManager {
  var showAuthSheet = false

  var isAuthenticated: Bool { Clerk.shared.user != nil }
  var isGuest: Bool { Clerk.shared.user == nil }
  var userId: String? { Clerk.shared.user?.id }

  var onUserIDChanged: ((String) -> Void)?
  var onLogout: (() -> Void)?

  func getToken() async -> String? {
    try? await Clerk.shared.session?.getToken()
  }

  func signOut() async {
    try? await Clerk.shared.auth.signOut()
    onLogout?()
  }
}
