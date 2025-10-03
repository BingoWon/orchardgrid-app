/**
 * LoginView.swift
 * OrchardGrid Login Interface
 */

import SwiftUI

struct LoginView: View {
  @Environment(AuthManager.self) private var authManager
  @State private var email = ""
  @State private var password = ""
  @State private var showPassword = false
  @State private var showRegister = false

  var body: some View {
    Group {
      if showRegister {
        RegisterView(showLogin: $showRegister)
      } else {
        loginContent
      }
    }
  }

  private var loginContent: some View {
    ScrollView {
      VStack(spacing: adaptiveSpacing) {
        // Logo and title
        VStack(spacing: 12) {
          Image(systemName: "cpu.fill")
            .font(.system(size: adaptiveLogoSize))
            .foregroundStyle(.blue.gradient)

          Text("OrchardGrid")
            .font(.system(size: adaptiveTitleSize, weight: .bold, design: .rounded))

          Text("Distributed Apple Intelligence Computing")
            .font(adaptiveSubtitleFont)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
        .padding(.top, adaptiveTopPadding)

          // Login form
          VStack(spacing: 16) {
            // Email input
            TextField("Email", text: $email)
              .textFieldStyle(.roundedBorder)
              .textContentType(.emailAddress)
              #if os(iOS)
                .autocapitalization(.none)
                .keyboardType(.emailAddress)
              #endif

            // Password input
            HStack {
              if showPassword {
                TextField("Password", text: $password)
                  .textContentType(.password)
              } else {
                SecureField("Password", text: $password)
                  .textContentType(.password)
              }
              Button {
                showPassword.toggle()
              } label: {
                Image(systemName: showPassword ? "eye.slash" : "eye")
                  .foregroundStyle(.secondary)
              }
              .buttonStyle(.plain)
            }
            .textFieldStyle(.roundedBorder)

            // Sign In button
            Button {
              Task {
                await authManager.login(email: email, password: password)
              }
            } label: {
              Text("Sign In")
                .frame(maxWidth: .infinity)
                .frame(height: 44)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!isFormValid)

            // Divider
            HStack {
              Rectangle()
                .fill(Color.secondary.opacity(0.3))
                .frame(height: 1)
              Text("or")
                .font(.caption)
                .foregroundStyle(.secondary)
              Rectangle()
                .fill(Color.secondary.opacity(0.3))
                .frame(height: 1)
            }

            // Google Sign In button
            Button {
              Task {
                await authManager.signInWithGoogle()
              }
            } label: {
              HStack {
                Image(systemName: "globe")
                Text("Continue with Google")
              }
              .frame(maxWidth: .infinity)
              .frame(height: 44)
            }
            .buttonStyle(.bordered)
          }
          .frame(maxWidth: 400)

          // Error message
          if let error = authManager.lastError {
            Text(error)
              .font(.caption)
              .foregroundStyle(.red)
              .multilineTextAlignment(.center)
              .padding(.horizontal)
          }

        // Switch to register
        HStack {
          Text("Don't have an account?")
            .foregroundStyle(.secondary)
          Button("Create Account") {
            showRegister = true
          }
        }
        .font(.callout)
        .padding(.top, 20)
        .padding(.bottom, adaptiveBottomPadding)
      }
      .padding()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    #if os(macOS)
      .background(Color(nsColor: .windowBackgroundColor))
    #else
      .background(Color(.systemBackground))
    #endif
  }

  // MARK: - Adaptive Layout

  private var adaptiveSpacing: CGFloat {
    #if os(iOS)
      return UIScreen.main.bounds.height < 700 ? 16 : 24
    #else
      return 32
    #endif
  }

  private var adaptiveLogoSize: CGFloat {
    #if os(iOS)
      return UIScreen.main.bounds.height < 700 ? 48 : 64
    #else
      return 64
    #endif
  }

  private var adaptiveTitleSize: CGFloat {
    #if os(iOS)
      return UIScreen.main.bounds.height < 700 ? 28 : 36
    #else
      return 36
    #endif
  }

  private var adaptiveSubtitleFont: Font {
    #if os(iOS)
      return UIScreen.main.bounds.height < 700 ? .caption : .title3
    #else
      return .title3
    #endif
  }

  private var adaptiveTopPadding: CGFloat {
    #if os(iOS)
      return UIScreen.main.bounds.height < 700 ? 8 : 20
    #else
      return 0
    #endif
  }

  private var adaptiveBottomPadding: CGFloat {
    #if os(iOS)
      return UIScreen.main.bounds.height < 700 ? 8 : 20
    #else
      return 0
    #endif
  }

  private var isFormValid: Bool {
    !email.isEmpty && !password.isEmpty
  }
}

#Preview {
  LoginView()
    .environment(AuthManager())
}
