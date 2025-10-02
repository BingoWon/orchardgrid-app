/**
 * AuthManager.swift
 * OrchardGrid Authentication Manager
 *
 * Simplified email authentication for development
 */

import Foundation

@MainActor
@Observable
final class AuthManager {
  // Authentication state
  var isAuthenticated = false
  var currentUser: User?
  var authToken: String?
  var lastError: String?

  // API configuration
  private let apiURL = "https://orchardgrid-api.bingow.workers.dev"

  init() {
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

  // Sign in with email
  func signInWithEmail(_ email: String) async {
    guard !email.isEmpty else {
      lastError = "Email is required"
      return
    }

    do {
      let url = URL(string: "\(apiURL)/auth/email")!
      var request = URLRequest(url: url)
      request.httpMethod = "POST"
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")

      let body = ["email": email]
      request.httpBody = try JSONEncoder().encode(body)

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
      print("❌ Authentication failed: \(error)")
      lastError = error.localizedDescription
    }
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
