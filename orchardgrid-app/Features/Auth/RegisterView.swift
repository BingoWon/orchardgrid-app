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
    GeometryReader { geometry in
      ScrollView {
        VStack(spacing: 32) {
          Spacer(minLength: geometry.size.height * 0.08)

          // Header
          VStack(spacing: 8) {
            Image(systemName: "cpu.fill")
              .font(.system(size: 48))
              .foregroundStyle(.blue.gradient)

            Text("Create Account")
              .font(.system(size: 28, weight: .bold, design: .rounded))

            Text("Join OrchardGrid")
              .font(.subheadline)
              .foregroundStyle(.secondary)
          }

          // Form
          VStack(spacing: 16) {
            TextField("Name (optional)", text: $name)
              .textFieldStyle(.roundedBorder)
              .textContentType(.name)

            TextField("Email", text: $email)
              .textFieldStyle(.roundedBorder)
              .textContentType(.emailAddress)
            #if os(iOS)
              .autocapitalization(.none)
              .keyboardType(.emailAddress)
            #endif

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

            Text("Password must be at least 8 characters")
              .font(.caption)
              .foregroundStyle(.secondary)
              .frame(maxWidth: .infinity, alignment: .leading)

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
          }
          .padding(24)
          .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
          .frame(maxWidth: 400)

          // Error
          if let error = authManager.lastError {
            Text(error)
              .font(.caption)
              .foregroundStyle(.red)
              .multilineTextAlignment(.center)
          }

          // Login Link
          HStack(spacing: 4) {
            Text("Already have an account?")
              .foregroundStyle(.secondary)
            Button("Sign In") {
              showLogin = false
            }
          }
          .font(.callout)

          Spacer(minLength: geometry.size.height * 0.08)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, minHeight: geometry.size.height)
      }
    }
  }

  private var isFormValid: Bool {
    !email.isEmpty && !password.isEmpty && !confirmPassword.isEmpty && password.count >= 8
  }
}
