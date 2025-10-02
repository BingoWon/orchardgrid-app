/**
 * LoginView.swift
 * OrchardGrid Login Interface
 *
 * Sign in with Apple authentication
 */

import AuthenticationServices
import SwiftUI

struct LoginView: View {
  @Environment(AuthManager.self) private var authManager

  var body: some View {
    VStack(spacing: 40) {
      // Logo and title
      VStack(spacing: 16) {
        Image(systemName: "cpu.fill")
          .font(.system(size: 80))
          .foregroundStyle(.blue.gradient)

        Text("OrchardGrid")
          .font(.system(size: 48, weight: .bold, design: .rounded))

        Text("Distributed Apple Intelligence Computing")
          .font(.title3)
          .foregroundStyle(.secondary)
      }

      // Sign in button
      SignInWithAppleButton(.signIn) { request in
        request.requestedScopes = [.fullName, .email]
      } onCompletion: { result in
        switch result {
        case let .success(authorization):
          authManager.authorizationController(
            controller: ASAuthorizationController(authorizationRequests: []),
            didCompleteWithAuthorization: authorization
          )
        case let .failure(error):
          authManager.authorizationController(
            controller: ASAuthorizationController(authorizationRequests: []),
            didCompleteWithError: error
          )
        }
      }
      .signInWithAppleButtonStyle(.black)
      .frame(height: 50)
      .frame(maxWidth: 300)

      // Error message
      if let error = authManager.lastError {
        Text(error)
          .font(.caption)
          .foregroundStyle(.red)
          .multilineTextAlignment(.center)
      }

      Spacer()

      // Footer
      Text("By signing in, you agree to our Terms of Service and Privacy Policy")
        .font(.caption)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .padding(.horizontal)
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(nsColor: .windowBackgroundColor))
  }
}

#Preview {
  LoginView()
    .environment(AuthManager())
}
