/**
 * RegisterView.swift
 * Registration screen
 */

import SwiftUI

struct RegisterView: View {
  @Environment(AuthManager.self) private var auth
  @Environment(\.dismiss) private var dismiss
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass

  @State private var email = ""
  @State private var password = ""
  @State private var confirmPassword = ""

  private var isWideLayout: Bool {
    #if os(macOS)
      return true
    #else
      return horizontalSizeClass == .regular
    #endif
  }

  var body: some View {
    @Bindable var auth = auth

    NavigationStack {
      AuthLayout {
        VStack(spacing: 32) {
          AuthHeader(title: "Create account", subtitle: "Get started with OrchardGrid")

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

            AuthField(placeholder: "Confirm Password", text: $confirmPassword, isSecure: true)

            if !confirmPassword.isEmpty, password != confirmPassword {
              Text("Passwords don't match")
                .font(.caption)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            AuthButton(title: "Create Account", isEnabled: isFormValid && !auth.isLoading) {
              Task { await auth.register(email: email, password: password) }
            }
          }

          AuthLink(text: "Already have an account?", linkText: "Sign In") {
            dismiss()
          }
        }
      }
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
      }
    }
  }

  private var isFormValid: Bool {
    !email.isEmpty && !password.isEmpty && password == confirmPassword && password.count >= 8
  }
}

#Preview {
  RegisterView().environment(AuthManager())
}
