/**
 * LoginView.swift
 * Login screen (standalone, used for initial auth before guest mode)
 */

import SwiftUI

struct LoginView: View {
  @Environment(AuthManager.self) private var auth
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @State private var email = ""
  @State private var password = ""

  private var isWideLayout: Bool {
    #if os(macOS)
      return true
    #else
      return horizontalSizeClass == .regular
    #endif
  }

  var body: some View {
    @Bindable var auth = auth

    AuthLayout {
      VStack(spacing: 32) {
        AuthHeader(title: "Welcome back", subtitle: "Sign in to OrchardGrid")

        VStack(spacing: 12) {
          if let error = auth.lastError {
            AuthErrorBanner(message: error)
          }

          // Social Login - Side by side on wide screens
          if isWideLayout {
            HStack(spacing: 12) {
              SocialLoginButton(provider: .apple) {
                auth.loginWithApple()
              }
              SocialLoginButton(provider: .google) {
                auth.loginWithGoogle()
              }
            }
          } else {
            SocialLoginButton(provider: .apple) {
              auth.loginWithApple()
            }
            SocialLoginButton(provider: .google) {
              auth.loginWithGoogle()
            }
          }

          AuthDivider(text: "or continue with email")
            .padding(.vertical, 4)

          AuthField(placeholder: "Email", text: $email)
          #if os(iOS)
            .keyboardType(.emailAddress)
          #endif

          AuthField(placeholder: "Password", text: $password, isSecure: true)

          AuthButton(title: "Sign In", isEnabled: isFormValid && !auth.isLoading) {
            Task { await auth.login(email: email, password: password) }
          }
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
