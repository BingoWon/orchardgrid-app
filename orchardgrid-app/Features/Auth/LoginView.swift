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
    if showRegister {
      RegisterView(showLogin: $showRegister)
    } else {
      GeometryReader { geometry in
        ScrollView {
          VStack(spacing: 32) {
            Spacer(minLength: geometry.size.height * 0.1)

            // Header
            VStack(spacing: 8) {
              Image(systemName: "cpu.fill")
                .font(.system(size: 48))
                .foregroundStyle(.blue.gradient)

              Text("OrchardGrid")
                .font(.system(size: 28, weight: .bold, design: .rounded))

              Text("Distributed Apple Intelligence")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            // Form
            VStack(spacing: 16) {
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

            // Register Link
            HStack(spacing: 4) {
              Text("Don't have an account?")
                .foregroundStyle(.secondary)
              Button("Create Account") {
                showRegister = true
              }
            }
            .font(.callout)

            Spacer(minLength: geometry.size.height * 0.1)
          }
          .padding(.horizontal, 20)
          .frame(minHeight: geometry.size.height)
        }
      }
    }
  }

  private var isFormValid: Bool {
    !email.isEmpty && !password.isEmpty
  }
}

#Preview {
  LoginView()
    .environment(AuthManager())
}
