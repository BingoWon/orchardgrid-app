import AuthenticationServices
import ClerkKit
import SwiftUI

struct SignInView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.colorScheme) private var colorScheme

  @State private var mode: Mode = .signIn
  @State private var email = ""
  @State private var password = ""
  @State private var firstName = ""
  @State private var lastName = ""
  @State private var verificationCode = ""
  @State private var pendingSignUp: SignUp?
  @State private var isLoading = false
  @State private var errorMessage: String?

  private enum Mode {
    case signIn, signUp, verifyEmail
  }

  var body: some View {
    VStack(spacing: 0) {
      closeBar
      content
    }
    .frame(width: 400)
    .fixedSize(horizontal: false, vertical: true)
    .disabled(isLoading)
  }

  private var closeBar: some View {
    HStack {
      Spacer()
      Button { dismiss() } label: {
        Image(systemName: "xmark")
          .font(.system(size: 12, weight: .bold))
          .foregroundStyle(.secondary)
          .frame(width: 28, height: 28)
          .background(oauthButtonBackground)
          .clipShape(Circle())
      }
      .buttonStyle(.plain)
    }
    .padding(.trailing, 16)
    .padding(.top, 12)
  }

  @ViewBuilder
  private var content: some View {
    switch mode {
    case .signIn:
      signInContent
    case .signUp:
      signUpContent
    case .verifyEmail:
      verifyEmailContent
    }
  }

  // MARK: - Sign In

  private var signInContent: some View {
    VStack(spacing: 20) {
      logo
      titleGroup(
        title: "Sign in to OrchardGrid",
        subtitle: "Welcome back! Please sign in to continue"
      )
      oauthButtons
      divider
      emailSection
      actionButton(title: "Continue", disabled: email.isEmpty || password.isEmpty) {
        await signInWithEmail()
      }
      errorText
    }
    .padding(.horizontal, 28)
    .padding(.bottom, 8)
    .safeAreaInset(edge: .bottom) {
      footerLink(prompt: "Don't have an account?", action: "Sign up") {
        withAnimation(.easeInOut(duration: 0.2)) {
          mode = .signUp
          errorMessage = nil
        }
      }
    }
  }

  // MARK: - Sign Up

  private var signUpContent: some View {
    VStack(spacing: 20) {
      logo
      titleGroup(
        title: "Create your account",
        subtitle: "Welcome! Please fill in the details to get started."
      )
      oauthButtons
      divider
      nameFields
      emailSection
      actionButton(title: "Continue", disabled: email.isEmpty || password.isEmpty) {
        await signUpWithEmail()
      }
      errorText
    }
    .padding(.horizontal, 28)
    .padding(.bottom, 8)
    .safeAreaInset(edge: .bottom) {
      footerLink(prompt: "Already have an account?", action: "Sign in") {
        withAnimation(.easeInOut(duration: 0.2)) {
          mode = .signIn
          errorMessage = nil
        }
      }
    }
  }

  // MARK: - Email Verification

  private var verifyEmailContent: some View {
    VStack(spacing: 20) {
      logo
      titleGroup(
        title: "Verify your email",
        subtitle: "Enter the verification code sent to \(email)"
      )
      fieldGroup(label: "Verification code") {
        TextField("Enter code", text: $verificationCode)
          .textContentType(.oneTimeCode)
          .onSubmit { Task { await verifyEmail() } }
      }
      actionButton(title: "Verify", disabled: verificationCode.isEmpty) {
        await verifyEmail()
      }
      errorText
    }
    .padding(.horizontal, 28)
    .padding(.bottom, 8)
    .safeAreaInset(edge: .bottom) {
      footerLink(prompt: "Wrong email?", action: "Go back") {
        withAnimation(.easeInOut(duration: 0.2)) {
          mode = .signUp
          verificationCode = ""
          pendingSignUp = nil
          errorMessage = nil
        }
      }
    }
  }

  // MARK: - Shared Components

  private var logo: some View {
    Image(nsImage: NSApp.applicationIconImage)
      .resizable()
      .scaledToFit()
      .frame(width: 52, height: 52)
      .clipShape(RoundedRectangle(cornerRadius: 12))
  }

  private func titleGroup(title: String, subtitle: String) -> some View {
    VStack(spacing: 6) {
      Text(title)
        .font(.title3.weight(.bold))
      Text(subtitle)
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }
  }

  private var oauthButtons: some View {
    HStack(spacing: 8) {
      oauthButton(label: "Apple", icon: "AppleLogo") {
        await oauthFlow { try await Clerk.shared.auth.signInWithApple() }
      }
      oauthButton(label: "Google", icon: "GoogleLogo") {
        await oauthFlow { try await Clerk.shared.auth.signInWithOAuth(provider: .google) }
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
      HStack(spacing: 8) {
        Image(icon)
          .resizable()
          .scaledToFit()
          .frame(width: 16, height: 16)
        Text(label)
          .font(.subheadline.weight(.medium))
      }
      .frame(maxWidth: .infinity)
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

  private var divider: some View {
    HStack(spacing: 12) {
      Rectangle().fill(dividerColor).frame(height: 1)
      Text("or")
        .font(.caption)
        .foregroundStyle(.secondary)
      Rectangle().fill(dividerColor).frame(height: 1)
    }
  }

  private var nameFields: some View {
    HStack(spacing: 12) {
      fieldGroup(label: "First name", optional: true) {
        TextField("First name", text: $firstName)
          .textContentType(.givenName)
      }
      fieldGroup(label: "Last name", optional: true) {
        TextField("Last name", text: $lastName)
          .textContentType(.familyName)
      }
    }
  }

  private var emailSection: some View {
    VStack(alignment: .leading, spacing: 14) {
      fieldGroup(label: "Email address") {
        TextField("Enter your email address", text: $email)
          .textContentType(.emailAddress)
      }
      fieldGroup(label: "Password") {
        SecureField("Enter your password", text: $password)
          .textContentType(mode == .signUp ? .newPassword : .password)
          .onSubmit {
            Task {
              if mode == .signIn { await signInWithEmail() }
              else { await signUpWithEmail() }
            }
          }
      }
    }
  }

  private func fieldGroup<Content: View>(
    label: String,
    optional: Bool = false,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 4) {
        Text(label)
          .font(.subheadline.weight(.medium))
        if optional {
          Text("Optional")
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
      }
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

  private func actionButton(
    title: String,
    disabled: Bool,
    action: @escaping () async -> Void
  ) -> some View {
    Button {
      Task { await action() }
    } label: {
      HStack(spacing: 6) {
        if isLoading {
          ProgressView()
            .controlSize(.small)
            .tint(.white)
        }
        Text(title)
          .font(.subheadline.weight(.semibold))
        Image(systemName: "arrowtriangle.right.fill")
          .font(.system(size: 7))
      }
      .frame(maxWidth: .infinity)
      .frame(height: 38)
      .foregroundStyle(.white)
      .background(accentButtonColor)
      .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    .buttonStyle(.plain)
    .disabled(disabled)
    .opacity(disabled ? 0.6 : 1)
  }

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

  private func footerLink(
    prompt: String,
    action: String,
    handler: @escaping () -> Void
  ) -> some View {
    VStack(spacing: 0) {
      Divider()
      HStack(spacing: 4) {
        Text(prompt)
          .font(.caption)
          .foregroundStyle(.secondary)
        Button(action, action: handler)
          .font(.caption.weight(.medium))
          .foregroundStyle(Color.accentColor)
          .buttonStyle(.plain)
      }
      .padding(.vertical, 14)
    }
  }

  // MARK: - Colors

  private var oauthButtonBackground: Color {
    colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.02)
  }

  private var borderColor: Color {
    colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.12)
  }

  private var dividerColor: Color {
    colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08)
  }

  private var inputBackground: Color {
    colorScheme == .dark ? Color.white.opacity(0.05) : .white
  }

  private var inputBorderColor: Color {
    colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.15)
  }

  private var accentButtonColor: Color {
    colorScheme == .dark
      ? Color(red: 0.45, green: 0.35, blue: 0.9)
      : Color(red: 0.4, green: 0.3, blue: 0.85)
  }

  // MARK: - Actions

  private func isUserCancellation(_ error: Error) -> Bool {
    let nsError = error as NSError
    switch (nsError.domain, nsError.code) {
    case (ASWebAuthenticationSessionError.errorDomain, ASWebAuthenticationSessionError.canceledLogin.rawValue),
         (ASAuthorizationError.errorDomain, ASAuthorizationError.canceled.rawValue),
         (ASAuthorizationError.errorDomain, ASAuthorizationError.unknown.rawValue):
      return true
    default:
      return Task.isCancelled
    }
  }

  @MainActor
  private func oauthFlow(_ action: () async throws -> some Any) async {
    isLoading = true
    errorMessage = nil
    defer { isLoading = false }
    do {
      _ = try await action()
      dismiss()
    } catch {
      if !isUserCancellation(error) { errorMessage = error.localizedDescription }
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
  private func signUpWithEmail() async {
    guard !email.isEmpty, !password.isEmpty else { return }
    isLoading = true
    errorMessage = nil
    defer { isLoading = false }
    do {
      let signUp = try await Clerk.shared.auth.signUp(
        emailAddress: email,
        password: password,
        firstName: firstName.isEmpty ? nil : firstName,
        lastName: lastName.isEmpty ? nil : lastName
      )
      switch signUp.status {
      case .complete:
        dismiss()
      case .missingRequirements:
        pendingSignUp = try await signUp.sendEmailCode()
        withAnimation(.easeInOut(duration: 0.2)) { mode = .verifyEmail }
      default:
        errorMessage = "Unexpected status. Please try again."
      }
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  @MainActor
  private func verifyEmail() async {
    guard let pending = pendingSignUp, !verificationCode.isEmpty else { return }
    isLoading = true
    errorMessage = nil
    defer { isLoading = false }
    do {
      let result = try await pending.verifyEmailCode(verificationCode)
      if result.status == .complete { dismiss() }
    } catch {
      errorMessage = error.localizedDescription
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
