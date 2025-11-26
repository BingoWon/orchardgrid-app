/**
 * GuestFeaturePrompt.swift
 * Reusable component for prompting guest users to sign in
 */

import SwiftUI

struct GuestFeaturePrompt: View {
  let icon: String
  let title: String
  let description: String
  let benefits: [String]
  let buttonTitle: String

  @Environment(AuthManager.self) private var authManager

  var body: some View {
    VStack(spacing: 20) {
      // Icon
      Image(systemName: icon)
        .font(.system(size: 48))
        .foregroundStyle(.secondary)

      // Title
      Text(title)
        .font(.title2)
        .fontWeight(.semibold)

      // Description
      Text(description)
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)

      // Benefits
      VStack(alignment: .leading, spacing: 8) {
        ForEach(benefits, id: \.self) { benefit in
          HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
              .foregroundStyle(.green)
              .font(.subheadline)
            Text(benefit)
              .font(.subheadline)
              .foregroundStyle(.secondary)
          }
        }
      }
      .padding(.vertical, 8)

      // Sign In Button
      Button {
        authManager.showSignInSheet = true
      } label: {
        Text(buttonTitle)
          .font(.headline)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 12)
      }
      .buttonStyle(.borderedProminent)
      .padding(.horizontal, 32)
    }
    .padding(24)
    .frame(maxWidth: .infinity)
    .glassEffect(in: .rect(cornerRadius: 16, style: .continuous))
  }
}

// MARK: - Sign In Sheet

struct SignInSheet: View {
  @Environment(AuthManager.self) private var authManager
  @Environment(\.dismiss) private var dismiss
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
    NavigationStack {
      ScrollView {
        VStack(spacing: 24) {
          // Header
          AuthHeader(title: "Welcome back", subtitle: "Sign in to unlock all features")
            .padding(.top, 16)

          // Error
          if let error = authManager.lastError {
            AuthErrorBanner(message: error)
              .padding(.horizontal)
          }

          // Social Login - Side by side on wide screens
          VStack(spacing: 12) {
            if isWideLayout {
              HStack(spacing: 12) {
                SocialLoginButton(provider: .apple) {
                  authManager.loginWithApple()
                }
                SocialLoginButton(provider: .google) {
                  authManager.loginWithGoogle()
                }
              }
            } else {
              SocialLoginButton(provider: .apple) {
                authManager.loginWithApple()
              }
              SocialLoginButton(provider: .google) {
                authManager.loginWithGoogle()
              }
            }
          }
          .padding(.horizontal)

          // Divider
          AuthDivider(text: "or continue with email")
            .padding(.horizontal)

          // Email Login
          VStack(spacing: 12) {
            AuthField(placeholder: "Email", text: $email)
              #if os(iOS)
                .keyboardType(.emailAddress)
              #endif

            AuthField(placeholder: "Password", text: $password, isSecure: true)

            AuthButton(
              title: "Sign In",
              isEnabled: !email.isEmpty && !password.isEmpty && !authManager.isLoading
            ) {
              Task { await authManager.login(email: email, password: password) }
            }
          }
          .padding(.horizontal)

          // Register Link
          AuthLink(text: "Don't have an account?", linkText: "Sign Up") {
            authManager.showRegisterView = true
          }
        }
        .padding(.bottom, 24)
      }
      .navigationTitle("Sign In")
      #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") {
            dismiss()
          }
        }
      }
      .sheet(isPresented: Binding(
        get: { authManager.showRegisterView },
        set: { authManager.showRegisterView = $0 }
      )) {
        RegisterView()
          .environment(authManager)
      }
      .onChange(of: authManager.isAuthenticated) { _, isAuth in
        if isAuth {
          dismiss()
        }
      }
    }
  }
}

#Preview("Guest Prompt") {
  GuestFeaturePrompt(
    icon: "server.rack",
    title: "See All Your Devices",
    description: "Sign in to view and manage devices across all your Apple devices.",
    benefits: [
      "Track contributions from each device",
      "View processing statistics",
      "Real-time status updates",
    ],
    buttonTitle: "Sign In to View Devices"
  )
  .environment(AuthManager())
  .padding()
}

#Preview("Sign In Sheet") {
  SignInSheet()
    .environment(AuthManager())
}

