/**
 * LoginView.swift
 * Login screen
 */

import SwiftUI

struct LoginView: View {
  @Environment(AuthManager.self) private var auth
  @State private var email = ""
  @State private var password = ""

  var body: some View {
    @Bindable var auth = auth

    AuthLayout {
      VStack(spacing: 32) {
        AuthHeader(title: "OrchardGrid", subtitle: "GPU Device Management")
          .padding(.top, 20)

        VStack(spacing: 16) {
          if let error = auth.lastError {
            AuthErrorBanner(message: error)
          }

          AuthField(placeholder: "Email", text: $email)
            #if os(iOS)
              .keyboardType(.emailAddress)
            #endif

          AuthField(placeholder: "Password", text: $password, isSecure: true)

          AuthButton(title: "Sign In", isEnabled: isFormValid && !auth.isLoading) {
            Task { await auth.login(email: email, password: password) }
          }

          AuthDivider(text: "or")

          GoogleButton { auth.loginWithGoogle() }
        }

        AuthLink(text: "Don't have an account?", linkText: "Sign Up") {
          auth.showRegisterView = true
        }
      }
    }
    .sheet(isPresented: $auth.showRegisterView) {
      RegisterView().environment(auth)
    }
  }

  private var isFormValid: Bool {
    !email.isEmpty && !password.isEmpty
  }
}

#Preview {
  LoginView().environment(AuthManager())
}
