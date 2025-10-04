/**
 * AuthManager.swift
 * OrchardGrid Authentication Manager
 */

import Foundation

@MainActor
@Observable
final class AuthManager {
  // Authentication state
  enum AuthState: Equatable {
    case loading
    case authenticated(User)
    case unauthenticated
  }

  var authState: AuthState = .loading
  var currentUser: User?
  var authToken: String?
  var lastError: String?

  // Computed property for backward compatibility
  var isAuthenticated: Bool {
    if case .authenticated = authState {
      return true
    }
    return false
  }

  // API configuration
  private let apiURL = Config.apiBaseURL

  // Callback for user ID changes
  var onUserIDChanged: ((String) -> Void)?

  init() {
    checkAuthStatus()
  }

  // Check if user is already authenticated
  func checkAuthStatus() {
    if let token = UserDefaultsManager.getToken() {
      authToken = token
      Task {
        await fetchUserInfo()
      }
    } else {
      authState = .unauthenticated
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
      UserDefaultsManager.saveToken(response.token)
      authToken = response.token
      authState = .authenticated(response.user)
      currentUser = response.user
      lastError = nil

      Logger.success(.auth, "Registration successful: \(response.user.email)")
      onUserIDChanged?(response.user.id)
    } catch {
      Logger.error(.auth, "Registration failed: \(error)")
      lastError = error.localizedDescription
      authState = .unauthenticated
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
      UserDefaultsManager.saveToken(response.token)
      authToken = response.token
      authState = .authenticated(response.user)
      currentUser = response.user
      lastError = nil

      Logger.success(.auth, "Login successful: \(response.user.email)")
      onUserIDChanged?(response.user.id)
    } catch {
      Logger.error(.auth, "Login failed: \(error)")
      lastError = error.localizedDescription
      authState = .unauthenticated
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

      authState = .authenticated(user)
      currentUser = user
      lastError = nil
      onUserIDChanged?(user.id)
    } catch {
      Logger.error(.auth, "Failed to fetch user info: \(error)")
      lastError = error.localizedDescription
      authState = .unauthenticated
      logout()
    }
  }

  // Logout
  func logout() {
    UserDefaultsManager.deleteToken()
    authToken = nil
    currentUser = nil
    authState = .unauthenticated
    Logger.log(.auth, "User logged out")
  }
}

// MARK: - Models

struct User: Codable, Equatable {
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

// MARK: - UserDefaults Manager

/// Simple token storage using UserDefaults
/// ⚠️ WARNING: This stores tokens in plain text and is NOT secure.
/// Only use this for development environments.
/// For production, use Keychain or other secure storage.
enum UserDefaultsManager {
  /// Environment-specific key for token storage
  private static var tokenKey: String {
    "auth_token_\(Config.environment.rawValue)"
  }

  /// Save authentication token to UserDefaults
  static func saveToken(_ token: String) {
    UserDefaults.standard.set(token, forKey: tokenKey)
    UserDefaults.standard.synchronize()
  }

  /// Retrieve authentication token from UserDefaults
  static func getToken() -> String? {
    UserDefaults.standard.string(forKey: tokenKey)
  }

  /// Delete authentication token from UserDefaults
  static func deleteToken() {
    UserDefaults.standard.removeObject(forKey: tokenKey)
    UserDefaults.standard.synchronize()
  }
}
