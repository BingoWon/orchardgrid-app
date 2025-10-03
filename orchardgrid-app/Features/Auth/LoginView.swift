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
    VStack(spacing: 32) {
      // Logo and title
      VStack(spacing: 16) {
        Image(systemName: "cpu.fill")
          .font(.system(size: 64))
          .foregroundStyle(.blue.gradient)

        Text("OrchardGrid")
          .font(.system(size: 36, weight: .bold, design: .rounded))

        Text("Distributed Apple Intelligence Computing")
          .font(.title3)
          .foregroundStyle(.secondary)
      }

      // Login form
      VStack(spacing: 16) {
        // Email input
        TextField("Email", text: $email)
          .textFieldStyle(.roundedBorder)
          .textContentType(.emailAddress)
        #if os(iOS)
          .autocapitalization(.none)
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
      .frame(maxWidth: 320)

      // Error message
      if let error = authManager.lastError {
        Text(error)
          .font(.caption)
          .foregroundStyle(.red)
          .multilineTextAlignment(.center)
          .padding(.horizontal)
      }

      Spacer()

      // Switch to register
      HStack {
        Text("Don't have an account?")
          .foregroundStyle(.secondary)
        Button("Create Account") {
          showRegister = true
        }
      }
      .font(.callout)
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(nsColor: .windowBackgroundColor))
  }

  private var isFormValid: Bool {
    !email.isEmpty && !password.isEmpty
  }
}

#Preview {
  LoginView()
    .environment(AuthManager())
}
