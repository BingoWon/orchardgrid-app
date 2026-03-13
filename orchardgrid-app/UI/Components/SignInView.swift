import ClerkKit
import SwiftUI

struct SignInView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.colorScheme) private var colorScheme
  @State private var email = ""
  @State private var password = ""
  @State private var isLoading = false
  @State private var errorMessage: String?

  var body: some View {
    VStack(spacing: 20) {
      logo
      titleSection
      oauthButtons
      divider
      emailSection
      continueButton
      errorText
    }
    .padding(.horizontal, 28)
    .padding(.top, 32)
    .padding(.bottom, 8)
    .frame(width: 400)
    .fixedSize(horizontal: false, vertical: true)
    .disabled(isLoading)
    .safeAreaInset(edge: .bottom) { footer }
  }

  // MARK: - Logo

  private var logo: some View {
    Image(nsImage: NSApp.applicationIconImage)
      .resizable()
      .scaledToFit()
      .frame(width: 52, height: 52)
      .clipShape(RoundedRectangle(cornerRadius: 12))
  }

  // MARK: - Title

  private var titleSection: some View {
    VStack(spacing: 6) {
      Text("Sign in to OrchardGrid")
        .font(.title3.weight(.bold))
      Text("Welcome back! Please sign in to continue")
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
  }

  // MARK: - OAuth Buttons

  private var oauthButtons: some View {
    VStack(spacing: 8) {
      oauthButton(label: "Continue with Google", icon: "GoogleLogo") {
        await signInWithGoogle()
      }
      oauthButton(label: "Continue with Apple", icon: "AppleLogo") {
        await signInWithApple()
      }
    }
  }

  private func oauthButton(
    label: String,
    icon: String,
    action: @escaping () async -> Void
  ) -> some View {
    Button {
      Task { await action() }
    } label: {
      HStack(spacing: 10) {
        Image(icon)
          .resizable()
          .scaledToFit()
          .frame(width: 16, height: 16)
        Text(label)
          .font(.subheadline.weight(.medium))
          .frame(maxWidth: .infinity)
      }
      .padding(.horizontal, 16)
      .frame(height: 38)
      .background(oauthButtonBackground)
      .clipShape(RoundedRectangle(cornerRadius: 8))
      .overlay(
        RoundedRectangle(cornerRadius: 8)
          .stroke(borderColor, lineWidth: 1)
      )
    }
    .buttonStyle(.plain)
  }

  // MARK: - Divider

  private var divider: some View {
    HStack(spacing: 12) {
      Rectangle().fill(dividerColor).frame(height: 1)
      Text("or")
        .font(.caption)
        .foregroundStyle(.secondary)
      Rectangle().fill(dividerColor).frame(height: 1)
    }
  }

  // MARK: - Email + Password

  private var emailSection: some View {
    VStack(alignment: .leading, spacing: 14) {
      fieldGroup(label: "Email address") {
        TextField("Enter your email address", text: $email)
          .textContentType(.emailAddress)
      }

      fieldGroup(label: "Password") {
        SecureField("Enter your password", text: $password)
          .textContentType(.password)
          .onSubmit { Task { await signInWithEmail() } }
      }
    }
  }

  private func fieldGroup<Content: View>(
    label: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(label)
        .font(.subheadline.weight(.medium))

      content()
        .textFieldStyle(.plain)
        .font(.subheadline)
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(inputBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
          RoundedRectangle(cornerRadius: 8)
            .stroke(inputBorderColor, lineWidth: 1)
        )
    }
  }

  // MARK: - Continue Button

  private var continueButton: some View {
    Button {
      Task { await signInWithEmail() }
    } label: {
      HStack(spacing: 6) {
        if isLoading {
          ProgressView()
            .controlSize(.small)
            .tint(.white)
        }
        Text("Continue")
          .font(.subheadline.weight(.semibold))
        Image(systemName: "arrowtriangle.right.fill")
          .font(.system(size: 7))
      }
      .frame(maxWidth: .infinity)
      .frame(height: 38)
      .foregroundStyle(.white)
      .background(continueColor)
      .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    .buttonStyle(.plain)
    .disabled(email.isEmpty || password.isEmpty)
    .opacity(email.isEmpty || password.isEmpty ? 0.6 : 1)
  }

  // MARK: - Error

  @ViewBuilder
  private var errorText: some View {
    if let errorMessage {
      Text(errorMessage)
        .font(.caption)
        .foregroundStyle(.red)
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  // MARK: - Footer

  private var footer: some View {
    VStack(spacing: 0) {
      Divider()
      HStack(spacing: 4) {
        Text("Don't have an account?")
          .font(.caption)
          .foregroundStyle(.secondary)
        Button("Sign up") {
          Task { await signUpWithGoogle() }
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(Color.accentColor)
        .buttonStyle(.plain)
      }
      .padding(.vertical, 14)
    }
  }

  // MARK: - Colors

  private var oauthButtonBackground: Color {
    colorScheme == .dark
      ? Color.white.opacity(0.05)
      : Color.black.opacity(0.02)
  }

  private var borderColor: Color {
    colorScheme == .dark
      ? Color.white.opacity(0.15)
      : Color.black.opacity(0.12)
  }

  private var dividerColor: Color {
    colorScheme == .dark
      ? Color.white.opacity(0.1)
      : Color.black.opacity(0.08)
  }

  private var inputBackground: Color {
    colorScheme == .dark
      ? Color.white.opacity(0.05)
      : .white
  }

  private var inputBorderColor: Color {
    colorScheme == .dark
      ? Color.white.opacity(0.15)
      : Color.black.opacity(0.15)
  }

  private var continueColor: Color {
    colorScheme == .dark
      ? Color(red: 0.45, green: 0.35, blue: 0.9)
      : Color(red: 0.4, green: 0.3, blue: 0.85)
  }

  // MARK: - Actions

  @MainActor
  private func signInWithGoogle() async {
    isLoading = true
    errorMessage = nil
    defer { isLoading = false }
    do {
      _ = try await Clerk.shared.auth.signInWithOAuth(provider: .google)
      dismiss()
    } catch {
      if !Task.isCancelled { errorMessage = error.localizedDescription }
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
      if !Task.isCancelled { errorMessage = error.localizedDescription }
    }
  }

  @MainActor
  private func signInWithEmail() async {
    guard !email.isEmpty, !password.isEmpty else { return }
    isLoading = true
    errorMessage = nil
    defer { isLoading = false }
    do {
      let signIn = try await Clerk.shared.auth.signInWithPassword(
        identifier: email, password: password
      )
      if signIn.status == .complete { dismiss() }
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  @MainActor
  private func signUpWithGoogle() async {
    isLoading = true
    errorMessage = nil
    defer { isLoading = false }
    do {
      _ = try await Clerk.shared.auth.signUpWithOAuth(provider: .google)
      dismiss()
    } catch {
      if !Task.isCancelled { errorMessage = error.localizedDescription }
    }
  }
}

#Preview("Dark") {
  SignInView()
    .preferredColorScheme(.dark)
}

#Preview("Light") {
  SignInView()
    .preferredColorScheme(.light)
}
