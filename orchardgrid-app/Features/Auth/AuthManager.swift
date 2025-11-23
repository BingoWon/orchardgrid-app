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
  private let urlSession = Config.urlSession

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

      let (data, _) = try await urlSession.data(for: request)
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
      request.httpBody = try JSONEncoder().encode(["email": email, "password": password])

      let (data, response) = try await urlSession.data(for: request)

      guard let httpResponse = response as? HTTPURLResponse else {
        Logger.error(.auth, "Login failed: Invalid response")
        lastError = "Unable to sign in. Please try again."
        authState = .unauthenticated
        return
      }

      // Handle non-200 responses with user‑friendly messages
      guard httpResponse.statusCode == 200 else {
        // Common case: wrong email or password → 统一成友好提示，不展示后端原始 JSON/技术信息
        if httpResponse.statusCode == 400 || httpResponse.statusCode == 401 {
          lastError = "Incorrect email or password. Please check and try again."
        } else {
          // 其它错误可以尝试用后端返回的消息（如果是可读文本），否则给出通用提示
          if let message = try? decodeAPIErrorMessage(from: data) {
            lastError = message
          } else {
            lastError = "Unable to sign in. Please try again later. (Error code \(httpResponse.statusCode))"
          }
        }

        Logger.error(
          .auth,
          "Login failed with status \(httpResponse.statusCode): \(lastError ?? "Unknown error")"
        )
        authState = .unauthenticated
        return
      }

      // Success path
      let authResponse = try JSONDecoder().decode(AuthResponse.self, from: data)

      // Save token and update state
      UserDefaultsManager.saveToken(authResponse.token)
      authToken = authResponse.token
      authState = .authenticated(authResponse.user)
      currentUser = authResponse.user
      lastError = nil

      Logger.success(.auth, "Login successful: \(authResponse.user.email)")
      onUserIDChanged?(authResponse.user.id)
    } catch {
      Logger.error(.auth, "Login failed: \(error)")

      // Avoid surfacing confusing low‑level decoding/network messages to users
      if (error as NSError).domain == NSCocoaErrorDomain {
        lastError = "Unable to sign in due to a temporary issue. Please try again."
      } else {
        lastError = "Unable to sign in. Please check your network connection and try again."
      }

      authState = .unauthenticated
    }
  }

  // Fetch user info from API
  private func fetchUserInfo() async {
    guard let token = authToken else { return }

    do {
      let url = URL(string: "\(apiURL)/auth/me")!
      var request = URLRequest(url: url)
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

      let (data, _) = try await urlSession.data(for: request)
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

// MARK: - Error Response Helpers

private struct APIErrorResponse: Codable {
  struct NestedError: Codable {
    let message: String?
    let type: String?
    let code: Int?
  }

  let error: String?
  let message: String?
  let type: String?
  let code: Int?
  let nestedError: NestedError?

  // Support payloads like { "error": { "message": "...", "type": "...", "code": 401 } }
  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    error = try container.decodeIfPresent(String.self, forKey: .error)
    message = try container.decodeIfPresent(String.self, forKey: .message)
    type = try container.decodeIfPresent(String.self, forKey: .type)
    code = try container.decodeIfPresent(Int.self, forKey: .code)

    if let nested = try container.decodeIfPresent(NestedError.self, forKey: .error) {
      nestedError = nested
    } else {
      nestedError = nil
    }
  }

  private enum CodingKeys: String, CodingKey {
    case error
    case message
    case type
    case code
  }
}

private func decodeAPIErrorMessage(from data: Data) throws -> String? {
  guard !data.isEmpty else { return nil }
  let decoder = JSONDecoder()
  if let errorResponse = try? decoder.decode(APIErrorResponse.self, from: data) {
    // 1) 优先使用顶层 message
    if let message = errorResponse.message, !message.isEmpty {
      return message
    }
    // 2) 然后使用嵌套 error.message
    if let nestedMessage = errorResponse.nestedError?.message, !nestedMessage.isEmpty {
      return nestedMessage
    }
    // 3) 最后退回到顶层 error 字段（如果是可读文本）
    if let error = errorResponse.error, !error.isEmpty {
      return error
    }
  }
  // Fallback: try plain‑text body
  if let text = String(data: data, encoding: .utf8), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
    return text
  }
  return nil
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
