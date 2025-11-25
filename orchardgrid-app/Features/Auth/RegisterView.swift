/**
 * RegisterView.swift
 * Registration screen
 */

import SwiftUI

struct RegisterView: View {
  @Environment(AuthManager.self) private var auth
  @Environment(\.dismiss) private var dismiss

  @State private var email = ""
  @State private var password = ""
  @State private var confirmPassword = ""

  var body: some View {
    @Bindable var auth = auth

    NavigationStack {
      AuthLayout {
        VStack(spacing: 32) {
          AuthHeader(title: "Create Account", subtitle: "Join OrchardGrid today")
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

            AuthDivider(text: "or")

            GoogleButton { auth.loginWithGoogle() }
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
    !email.isEmpty && !password.isEmpty && password == confirmPassword && password.count >= 6
  }
}

#Preview {
  RegisterView().environment(AuthManager())
}
