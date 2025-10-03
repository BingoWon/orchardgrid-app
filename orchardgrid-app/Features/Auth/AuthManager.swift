/**
 * AuthManager.swift
 * OrchardGrid Authentication Manager
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
  private let apiURL = Config.apiBaseURL

  // Callback for user ID changes
  var onUserIDChanged: ((String) -> Void)?

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

  // Register with email and password
  func register(email: String, password: String, confirmPassword: String, name: String?) async {
    guard !email.isEmpty, !password.isEmpty else {
      lastError = "Email and password are required"
      return
    }

    guard password == confirmPassword else {
      lastError = "Passwords do not match"
      return
    }

    guard password.count >= 8 else {
      lastError = "Password must be at least 8 characters"
      return
    }

    do {
      let url = URL(string: "\(apiURL)/auth/register")!
      var request = URLRequest(url: url)
      request.httpMethod = "POST"
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")

      var body: [String: String] = [
        "email": email,
        "password": password,
      ]
      if let name {
        body["name"] = name
      }
      request.httpBody = try JSONEncoder().encode(body)

      let (data, _) = try await URLSession.shared.data(for: request)
      let response = try JSONDecoder().decode(AuthResponse.self, from: data)

      // Save token
      KeychainManager.saveToken(response.token)
      authToken = response.token
      currentUser = response.user
      isAuthenticated = true
      lastError = nil

      Logger.success(.auth, "Registration successful: \(response.user.email)")
      onUserIDChanged?(response.user.id)
    } catch {
      Logger.error(.auth, "Registration failed: \(error)")
      lastError = error.localizedDescription
    }
  }

  // Login with email and password
  func login(email: String, password: String) async {
    guard !email.isEmpty, !password.isEmpty else {
      lastError = "Email and password are required"
      return
    }

    do {
      let url = URL(string: "\(apiURL)/auth/login")!
      var request = URLRequest(url: url)
      request.httpMethod = "POST"
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")

      let body = ["email": email, "password": password]
      request.httpBody = try JSONEncoder().encode(body)

      let (data, _) = try await URLSession.shared.data(for: request)
      let response = try JSONDecoder().decode(AuthResponse.self, from: data)

      // Save token
      KeychainManager.saveToken(response.token)
      authToken = response.token
      currentUser = response.user
      isAuthenticated = true
      lastError = nil

      Logger.success(.auth, "Login successful: \(response.user.email)")
      onUserIDChanged?(response.user.id)
    } catch {
      Logger.error(.auth, "Login failed: \(error)")
      lastError = error.localizedDescription
    }
  }

  // Sign in with Google
  func signInWithGoogle() async {
    // TODO: Implement Google Sign In SDK integration
    lastError = "Google Sign In not yet implemented"
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
      onUserIDChanged?(user.id)
    } catch {
      Logger.error(.auth, "Failed to fetch user info: \(error)")
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
  /// Use Bundle ID as service name for proper Keychain isolation
  private static var service: String {
    Bundle.main.bundleIdentifier ?? "com.orchardgrid.app"
  }

  /// Environment-specific account key
  private static var account: String {
    "auth_token_\(Config.environment.rawValue)"
  }

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
