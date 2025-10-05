/**
 * LoginView.swift
 * OrchardGrid Login Interface
 */

import SwiftUI

struct LoginView: View {
  @Environment(AuthManager.self) private var authManager
  @Environment(\.verticalSizeClass) private var verticalSizeClass
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
    ZStack {
      // Background
      #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
      #else
        Color(.systemBackground)
      #endif

      // Content
      ScrollView {
        VStack(spacing: 24) {
          // Logo and Title
          headerView
          #if os(macOS)
          .padding(.top, 40)
          #else
          .padding(.top, verticalSizeClass == .compact ? 20 : 40)
          #endif

          // Login Form
          loginForm
            .frame(maxWidth: 400)

          // Error Message
          if let error = authManager.lastError {
            Text(error)
              .font(.caption)
              .foregroundStyle(.red)
              .multilineTextAlignment(.center)
              .padding(.horizontal)
          }

          // Register Link
          registerLink

          Spacer(minLength: 20)
        }
        .padding()
      }
    }
    .ignoresSafeArea()
  }

  // MARK: - Header View

  private var headerView: some View {
    VStack(spacing: 12) {
      Image(systemName: "cpu.fill")
        .font(.system(size: 64))
        .foregroundStyle(.blue.gradient)
        .symbolEffect(.pulse)

      Text("OrchardGrid")
        .font(.system(size: 36, weight: .bold, design: .rounded))

      Text("Distributed Apple Intelligence Computing")
        .font(.title3)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }
  }

  // MARK: - Login Form

  private var loginForm: some View {
    VStack(spacing: 20) {
      VStack(spacing: 16) {
        // Email Input
        TextField("Email", text: $email)
          .textFieldStyle(.roundedBorder)
          .textContentType(.emailAddress)
        #if os(iOS)
          .autocapitalization(.none)
          .keyboardType(.emailAddress)
        #endif

        // Password Input
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

        // Sign In Button
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

        // Google Sign In Button
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
      .padding(32)
      .glassEffect(in: .rect(cornerRadius: 16, style: .continuous))
    }
  }

  // MARK: - Register Link

  private var registerLink: some View {
    HStack {
      Text("Don't have an account?")
        .foregroundStyle(.secondary)
      Button("Create Account") {
        showRegister = true
      }
    }
    .font(.callout)
  }

  // MARK: - Validation

  private var isFormValid: Bool {
    !email.isEmpty && !password.isEmpty
  }
}

#Preview {
  LoginView()
    .environment(AuthManager())
}
