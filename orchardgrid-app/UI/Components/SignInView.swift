import AuthenticationServices
import ClerkKit
import SwiftUI

struct SignInView: View {
  @Environment(\.dismiss) private var dismiss
  @State private var isLoading = false
  @State private var errorMessage: String?

  var body: some View {
    VStack(spacing: 24) {
      header
      buttons
      if let errorMessage {
        Text(errorMessage)
          .font(.caption)
          .foregroundStyle(.red)
          .multilineTextAlignment(.center)
      }
      Spacer()
    }
    .padding(32)
    .frame(width: 360, height: 320)
    .disabled(isLoading)
  }

  private var header: some View {
    VStack(spacing: 8) {
      Image(systemName: "square.grid.3x3.fill")
        .font(.system(size: 40))
        .foregroundStyle(.tint)
      Text("Sign in to OrchardGrid")
        .font(.title3.weight(.semibold))
    }
  }

  private var buttons: some View {
    VStack(spacing: 12) {
      SignInWithAppleButton(.signIn) { request in
        request.requestedScopes = [.email, .fullName]
      } onCompletion: { _ in }
        .signInWithAppleButtonStyle(.whiteOutline)
        .frame(height: 44)
        .overlay {
          Button {
            Task { await signInWithApple() }
          } label: {
            Color.clear
          }
          .buttonStyle(.plain)
        }

      Button {
        Task { await signInWithGoogle() }
      } label: {
        HStack(spacing: 8) {
          Image(systemName: "globe")
            .font(.body.weight(.medium))
          Text("Sign in with Google")
            .font(.body.weight(.medium))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
          RoundedRectangle(cornerRadius: 8)
            .stroke(.separator, lineWidth: 1)
        )
      }
      .buttonStyle(.plain)
    }
  }

  @MainActor
  private func signInWithApple() async {
    isLoading = true
    errorMessage = nil
    defer { isLoading = false }

    do {
      _ = try await Clerk.shared.auth.signInWithApple()
      dismiss()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  @MainActor
  private func signInWithGoogle() async {
    isLoading = true
    errorMessage = nil
    defer { isLoading = false }

    do {
      _ = try await Clerk.shared.auth.signInWithOAuth(provider: .google)
      dismiss()
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}

#Preview {
  SignInView()
}
