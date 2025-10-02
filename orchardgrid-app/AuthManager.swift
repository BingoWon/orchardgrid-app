/**
 * AuthManager.swift
 * OrchardGrid Authentication Manager
 *
 * Handles user authentication with Sign in with Apple
 */

import AuthenticationServices
import Foundation

@MainActor
@Observable
final class AuthManager: NSObject {
  // Authentication state
  var isAuthenticated = false
  var currentUser: User?
  var authToken: String?

  // Error handling
  var lastError: String?

  // API configuration
  private let apiURL = "https://orchardgrid-api.bingow.workers.dev"

  override init() {
    super.init()
    checkAuthStatus()
  }

  // Check if user is already authenticated
  func checkAuthStatus() {
    if let token = KeychainManager.getToken() {
      authToken = token
      Task {
        await fetchUserInfo()
      }
    }
  }

  // Sign in with Apple
  func signInWithApple() {
    let provider = ASAuthorizationAppleIDProvider()
    let request = provider.createRequest()
    request.requestedScopes = [.fullName, .email]

    let controller = ASAuthorizationController(authorizationRequests: [request])
    controller.delegate = self
    controller.performRequests()
  }

  // Fetch user info from API
  private func fetchUserInfo() async {
    guard let token = authToken else { return }

    do {
      let url = URL(string: "\(apiURL)/auth/me")!
      var request = URLRequest(url: url)
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

      let (data, _) = try await URLSession.shared.data(for: request)
      let user = try JSONDecoder().decode(User.self, from: data)

      currentUser = user
      isAuthenticated = true
      lastError = nil
    } catch {
      print("❌ Failed to fetch user info: \(error)")
      lastError = error.localizedDescription
      logout()
    }
  }

  // Logout
  func logout() {
    KeychainManager.deleteToken()
    authToken = nil
    currentUser = nil
    isAuthenticated = false
  }
}

// MARK: - ASAuthorizationControllerDelegate

extension AuthManager: ASAuthorizationControllerDelegate {
  func authorizationController(
    controller _: ASAuthorizationController,
    didCompleteWithAuthorization authorization: ASAuthorization
  ) {
    guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
      return
    }

    guard let identityToken = credential.identityToken,
          let tokenString = String(data: identityToken, encoding: .utf8)
    else {
      lastError = "Failed to get identity token"
      return
    }

    Task {
      await authenticateWithBackend(
        identityToken: tokenString,
        userIdentifier: credential.user,
        fullName: credential.fullName,
        email: credential.email
      )
    }
  }

  func authorizationController(
    controller _: ASAuthorizationController,
    didCompleteWithError error: Error
  ) {
    print("❌ Sign in with Apple failed: \(error)")
    lastError = error.localizedDescription
  }

  // Authenticate with backend
  private func authenticateWithBackend(
    identityToken: String,
    userIdentifier: String,
    fullName: PersonNameComponents?,
    email: String?
  ) async {
    do {
      let url = URL(string: "\(apiURL)/auth/apple")!
      var request = URLRequest(url: url)
      request.httpMethod = "POST"
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")

      let body: [String: Any] = [
        "id_token": identityToken,
        "user_identifier": userIdentifier,
        "full_name": fullName.map {
          [
            "given_name": $0.givenName ?? "",
            "family_name": $0.familyName ?? "",
          ]
        } ?? [:],
        "email": email ?? "",
      ]

      request.httpBody = try JSONSerialization.data(withJSONObject: body)

      let (data, _) = try await URLSession.shared.data(for: request)
      let response = try JSONDecoder().decode(AuthResponse.self, from: data)

      // Save token
      KeychainManager.saveToken(response.token)
      authToken = response.token
      currentUser = response.user
      isAuthenticated = true
      lastError = nil

      print("✅ Authentication successful: \(response.user.email)")
    } catch {
      print("❌ Backend authentication failed: \(error)")
      lastError = error.localizedDescription
    }
  }
}

// MARK: - Models

struct User: Codable {
  let id: String
  let email: String
  let name: String?
  let avatarUrl: String?

  enum CodingKeys: String, CodingKey {
    case id, email, name
    case avatarUrl = "avatar_url"
  }
}

struct AuthResponse: Codable {
  let token: String
  let user: User
}

// MARK: - Keychain Manager

enum KeychainManager {
  private static let service = "com.orchardgrid.app"
  private static let account = "auth_token"

  static func saveToken(_ token: String) {
    let data = Data(token.utf8)
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecValueData as String: data,
    ]

    SecItemDelete(query as CFDictionary)
    SecItemAdd(query as CFDictionary, nil)
  }

  static func getToken() -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecReturnData as String: true,
    ]

    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)

    guard status == errSecSuccess,
          let data = result as? Data,
          let token = String(data: data, encoding: .utf8)
    else {
      return nil
    }

    return token
  }

  static func deleteToken() {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]

    SecItemDelete(query as CFDictionary)
  }
}
