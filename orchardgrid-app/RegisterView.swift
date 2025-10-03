/**
 * RegisterView.swift
 * OrchardGrid Registration Interface
 */

import SwiftUI

struct RegisterView: View {
  @Environment(AuthManager.self) private var authManager
  @State private var email = ""
  @State private var password = ""
  @State private var confirmPassword = ""
  @State private var name = ""
  @State private var showPassword = false
  @State private var showConfirmPassword = false
  @Binding var showLogin: Bool

  var body: some View {
    VStack(spacing: 32) {
      // Logo and title
      VStack(spacing: 16) {
        Image(systemName: "cpu.fill")
          .font(.system(size: 64))
          .foregroundStyle(.blue.gradient)

        Text("Create Account")
          .font(.system(size: 36, weight: .bold, design: .rounded))

        Text("Join OrchardGrid")
          .font(.title3)
          .foregroundStyle(.secondary)
      }

      // Registration form
      VStack(spacing: 16) {
        // Name input
        TextField("Name (optional)", text: $name)
          .textFieldStyle(.roundedBorder)
          .textContentType(.name)

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
              .textContentType(.newPassword)
          } else {
            SecureField("Password", text: $password)
              .textContentType(.newPassword)
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

        // Confirm password input
        HStack {
          if showConfirmPassword {
            TextField("Confirm Password", text: $confirmPassword)
              .textContentType(.newPassword)
          } else {
            SecureField("Confirm Password", text: $confirmPassword)
              .textContentType(.newPassword)
          }
          Button {
            showConfirmPassword.toggle()
          } label: {
            Image(systemName: showConfirmPassword ? "eye.slash" : "eye")
              .foregroundStyle(.secondary)
          }
          .buttonStyle(.plain)
        }
        .textFieldStyle(.roundedBorder)

        // Password requirements
        Text("Password must be at least 8 characters")
          .font(.caption)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)

        // Register button
        Button {
          Task {
            await authManager.register(
              email: email,
              password: password,
              confirmPassword: confirmPassword,
              name: name.isEmpty ? nil : name
            )
          }
        } label: {
          Text("Create Account")
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

      // Switch to login
      HStack {
        Text("Already have an account?")
          .foregroundStyle(.secondary)
        Button("Sign In") {
          showLogin = true
        }
      }
      .font(.callout)
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(nsColor: .windowBackgroundColor))
  }

  private var isFormValid: Bool {
    !email.isEmpty && !password.isEmpty && !confirmPassword.isEmpty && password.count >= 8
  }
}
