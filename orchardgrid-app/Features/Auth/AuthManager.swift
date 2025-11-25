/**
 * AuthManager.swift
 * OrchardGrid Authentication Manager
 */

import AuthenticationServices
import Foundation
import GoogleSignIn

@MainActor
@Observable
final class AuthManager {
  enum AuthState: Equatable {
    case loading
    case authenticated(User)
    case unauthenticated
  }

  var authState: AuthState = .loading
  var currentUser: User?
  var authToken: String?
  var lastError: String?
  var isLoading = false
  var showRegisterView = false

  var isAuthenticated: Bool {
    if case .authenticated = authState { return true }
    return false
  }

  var onUserIDChanged: ((String) -> Void)?
  var onLogout: (() -> Void)?

  init() {
    checkAuthStatus()
  }

  func checkAuthStatus() {
    if let token = TokenStorage.get() {
      authToken = token
      Task { await fetchUserInfo() }
    } else {
      GIDSignIn.sharedInstance.restorePreviousSignIn { [weak self] user, _ in
        Task { @MainActor in
          if let idToken = user?.idToken?.tokenString {
            await self?.authenticateWithGoogle(idToken: idToken)
          } else {
            self?.authState = .unauthenticated
          }
        }
      }
    }
  }

  // MARK: - Email/Password

  func register(email: String, password: String) async {
    guard !email.isEmpty, !password.isEmpty else {
      lastError = "Email and password are required"
      return
    }

    isLoading = true
    defer { isLoading = false }

    do {
      let response: AuthResponse = try await post(
        "/auth/register",
        body: ["email": email, "password": password]
      )
      handleAuthSuccess(response)
      showRegisterView = false
    } catch {
      handleAuthError(error)
    }
  }

  func login(email: String, password: String) async {
    guard !email.isEmpty, !password.isEmpty else {
      lastError = "Email and password are required"
      return
    }

    isLoading = true
    defer { isLoading = false }

    do {
      let response: AuthResponse = try await post(
        "/auth/login",
        body: ["email": email, "password": password]
      )
      handleAuthSuccess(response)
    } catch {
      handleAuthError(error)
    }
  }

  func logout() {
    onLogout?()
    GIDSignIn.sharedInstance.signOut()
    TokenStorage.delete()
    authToken = nil
    currentUser = nil
    authState = .unauthenticated
  }

  // MARK: - Apple Sign-In

  func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
    switch result {
    case let .success(authorization):
      guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
            let identityToken = credential.identityToken,
            let idToken = String(data: identityToken, encoding: .utf8)
      else {
        lastError = "Failed to get Apple credentials"
        return
      }

      let email = credential.email
      let name = [credential.fullName?.givenName, credential.fullName?.familyName]
        .compactMap { $0 }
        .joined(separator: " ")
        .nilIfEmpty

      Task {
        await authenticateWithApple(idToken: idToken, email: email, name: name)
      }

    case let .failure(error):
      if (error as NSError).code != ASAuthorizationError.canceled.rawValue {
        lastError = error.localizedDescription
        Logger.error(.auth, "Apple Sign-In failed: \(error.localizedDescription)")
      } else {
        Logger.log(.auth, "Apple Sign-In canceled by user")
      }
    }
  }

  private func authenticateWithApple(idToken: String, email: String?, name: String?) async {
    Logger.log(.auth, "Authenticating with backend...")
    isLoading = true
    defer { isLoading = false }

    do {
      var body: [String: String] = ["idToken": idToken]
      if let email { body["email"] = email }
      if let name { body["name"] = name }

      let response: AuthResponse = try await post("/auth/apple", body: body)
      Logger.success(.auth, "Backend authentication successful")
      handleAuthSuccess(response)
      showRegisterView = false
    } catch {
      Logger.error(.auth, "Backend authentication failed: \(error.localizedDescription)")
      handleAuthError(error)
    }
  }

  // MARK: - Google Sign-In

  func loginWithGoogle() {
    isLoading = true

    #if os(iOS)
      guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
            let root = scene.windows.first?.rootViewController
      else {
        lastError = "Unable to present sign-in"
        isLoading = false
        return
      }
      GIDSignIn.sharedInstance.signIn(withPresenting: root) { [weak self] result, error in
        Task { @MainActor in await self?.handleGoogleResult(result, error) }
      }
    #else
      guard let window = NSApplication.shared.windows.first else {
        lastError = "Unable to present sign-in"
        isLoading = false
        return
      }
      GIDSignIn.sharedInstance.signIn(withPresenting: window) { [weak self] result, error in
        Task { @MainActor in await self?.handleGoogleResult(result, error) }
      }
    #endif
  }

  private func handleGoogleResult(_ result: GIDSignInResult?, _ error: Error?) async {
    defer { isLoading = false }

    if let error {
      if (error as NSError).code != GIDSignInError.canceled.rawValue {
        lastError = error.localizedDescription
        Logger.error(.auth, "Google Sign-In failed: \(error.localizedDescription)")
      } else {
        Logger.log(.auth, "Google Sign-In canceled by user")
      }
      return
    }

    guard let idToken = result?.user.idToken?.tokenString else {
      lastError = "Failed to get authentication token"
      Logger.error(.auth, "Google Sign-In succeeded but ID token is missing")
      return
    }

    Logger.success(
      .auth,
      "Google Sign-In succeeded. User: \(result?.user.profile?.email ?? "unknown")"
    )
    await authenticateWithGoogle(idToken: idToken)
  }

  private func authenticateWithGoogle(idToken: String) async {
    Logger.log(.auth, "Authenticating with backend...")
    do {
      let response: AuthResponse = try await post("/auth/google", body: ["idToken": idToken])
      Logger.success(.auth, "Backend authentication successful")
      handleAuthSuccess(response)
      showRegisterView = false
    } catch {
      Logger.error(.auth, "Backend authentication failed: \(error.localizedDescription)")
      handleAuthError(error)
    }
  }

  // MARK: - Private

  private func fetchUserInfo() async {
    guard let token = authToken else { return }

    do {
      var request = URLRequest(url: URL(string: "\(Config.apiBaseURL)/auth/me")!)
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

      let (data, _) = try await Config.urlSession.data(for: request)
      let user = try JSONDecoder().decode(User.self, from: data)

      authState = .authenticated(user)
      currentUser = user
      lastError = nil
      onUserIDChanged?(user.id)
    } catch {
      logout()
    }
  }

  private func handleAuthSuccess(_ response: AuthResponse) {
    TokenStorage.save(response.token)
    authToken = response.token
    authState = .authenticated(response.user)
    currentUser = response.user
    lastError = nil
    onUserIDChanged?(response.user.id)
  }

  private func handleAuthError(_ error: Error) {
    lastError = (error as? AuthError)?.message ?? "Authentication failed"
    authState = .unauthenticated
  }

  private func post<T: Decodable>(_ path: String, body: [String: String]) async throws -> T {
    var request = URLRequest(url: URL(string: "\(Config.apiBaseURL)\(path)")!)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode(body)

    let (data, response) = try await Config.urlSession.data(for: request)

    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
      let message = (try? JSONDecoder().decode(
        APIError.self,
        from: data
      ))?.message ?? "Request failed"
      throw AuthError(message: message)
    }

    return try JSONDecoder().decode(T.self, from: data)
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

struct AuthError: Error {
  let message: String
}

private struct APIError: Codable {
  let message: String?
}

private extension String {
  var nilIfEmpty: String? {
    isEmpty ? nil : self
  }
}

// MARK: - Token Storage

private enum TokenStorage {
  private static let key = "orchardgrid_auth_token"

  static func save(_ token: String) {
    UserDefaults.standard.set(token, forKey: key)
  }

  static func get() -> String? {
    UserDefaults.standard.string(forKey: key)
  }

  static func delete() {
    UserDefaults.standard.removeObject(forKey: key)
  }
}
