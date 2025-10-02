/**
 * LoginView.swift
 * OrchardGrid Login Interface
 *
 * Simplified email authentication
 */

import SwiftUI

struct LoginView: View {
  @Environment(AuthManager.self) private var authManager
  @State private var email = ""

  var body: some View {
    VStack(spacing: 40) {
      // Logo and title
      VStack(spacing: 16) {
        Image(systemName: "cpu.fill")
          .font(.system(size: 80))
          .foregroundStyle(.blue.gradient)

        Text("OrchardGrid")
          .font(.system(size: 48, weight: .bold, design: .rounded))

        Text("Distributed Apple Intelligence Computing")
          .font(.title3)
          .foregroundStyle(.secondary)
      }

      VStack(spacing: 16) {
        // Email input
        TextField("Email", text: $email)
          .textFieldStyle(.roundedBorder)
          .frame(maxWidth: 300)
          .textContentType(.emailAddress)

        Button {
          Task {
            await authManager.signInWithEmail(email)
          }
        } label: {
          Text("Sign In")
            .frame(maxWidth: .infinity)
            .frame(height: 50)
        }
        .buttonStyle(.borderedProminent)
        .disabled(email.isEmpty)

        // Test account hint
        VStack(spacing: 8) {
          Text("For testing, use:")
            .font(.caption)
            .foregroundStyle(.secondary)
          Text("test@orchardgrid.com")
            .font(.caption.monospaced())
            .foregroundStyle(.blue)
            .onTapGesture {
              email = "test@orchardgrid.com"
            }
        }
        .padding(.top, 8)
      }
      .frame(maxWidth: 300)

      // Error message
      if let error = authManager.lastError {
        Text(error)
          .font(.caption)
          .foregroundStyle(.red)
          .multilineTextAlignment(.center)
      }

      Spacer()

      // Footer
      Text("By signing in, you agree to our Terms of Service and Privacy Policy")
        .font(.caption)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .padding(.horizontal)
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(nsColor: .windowBackgroundColor))
  }
}

#Preview {
  LoginView()
    .environment(AuthManager())
}
