import AuthenticationServices
import ClerkKit
import SwiftUI

struct SignInView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.colorScheme) private var colorScheme
  @State private var email = ""
  @State private var password = ""
  @State private var isLoading = false
  @State private var errorMessage: String?
  @State private var showPassword = false

  var body: some View {
    VStack(spacing: 0) {
      VStack(spacing: 20) {
        logo
        titleSection
        oauthButtons
        divider
        emailSection
      }
      .padding(.horizontal, 28)
      .padding(.top, 32)
      .padding(.bottom, 24)

      footer
    }
    .frame(width: 400)
    .fixedSize(horizontal: false, vertical: true)
    .background(cardBackground)
    .clipShape(RoundedRectangle(cornerRadius: 16))
    .overlay(
      RoundedRectangle(cornerRadius: 16)
        .stroke(borderColor, lineWidth: 1)
    )
    .padding(24)
    .disabled(isLoading)
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
      oauthButton(
        label: "Continue with Google",
        icon: { GoogleIcon() }
      ) {
        await signInWithGoogle()
      }

      oauthButton(
        label: "Continue with Apple",
        icon: {
          Image(systemName: "apple.logo")
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(.primary)
        }
      ) {
        await signInWithApple()
      }
    }
  }

  private func oauthButton<Icon: View>(
    label: String,
    @ViewBuilder icon: () -> Icon,
    action: @escaping () async -> Void
  ) -> some View {
    Button {
      Task { await action() }
    } label: {
      HStack(spacing: 10) {
        icon()
          .frame(width: 20, height: 20)
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
          .stroke(oauthBorderColor, lineWidth: 1)
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

  // MARK: - Email Section

  private var emailSection: some View {
    VStack(alignment: .leading, spacing: 16) {
      VStack(alignment: .leading, spacing: 6) {
        Text("Email address")
          .font(.subheadline.weight(.medium))

        TextField("Enter your email address", text: $email)
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
          .textContentType(.emailAddress)
          .onSubmit {
            if !showPassword { withAnimation { showPassword = true } }
          }
      }

      if showPassword {
        VStack(alignment: .leading, spacing: 6) {
          Text("Password")
            .font(.subheadline.weight(.medium))

          SecureField("Enter your password", text: $password)
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
            .textContentType(.password)
            .onSubmit { Task { await signInWithEmail() } }
        }
        .transition(.move(edge: .top).combined(with: .opacity))
      }

      if let errorMessage {
        Text(errorMessage)
          .font(.caption)
          .foregroundStyle(.red)
          .multilineTextAlignment(.leading)
      }

      Button {
        if showPassword {
          Task { await signInWithEmail() }
        } else {
          withAnimation(.easeInOut(duration: 0.2)) { showPassword = true }
        }
      } label: {
        HStack(spacing: 6) {
          if isLoading {
            ProgressView()
              .controlSize(.small)
              .tint(.white)
          }
          Text("Continue")
            .font(.subheadline.weight(.semibold))
          Image(systemName: "arrow.right")
            .font(.caption.weight(.semibold))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 38)
        .foregroundStyle(.white)
        .background(continueButtonColor)
        .clipShape(RoundedRectangle(cornerRadius: 8))
      }
      .buttonStyle(.plain)
      .disabled(email.isEmpty || (showPassword && password.isEmpty))
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
          Task { await signUpFlow() }
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(Color.accentColor)
        .buttonStyle(.plain)
      }
      .padding(.vertical, 16)
    }
  }

  // MARK: - Colors

  private var cardBackground: Color {
    colorScheme == .dark
      ? Color(nsColor: .controlBackgroundColor)
      : .white
  }

  private var borderColor: Color {
    colorScheme == .dark
      ? Color.white.opacity(0.1)
      : Color.black.opacity(0.08)
  }

  private var oauthButtonBackground: Color {
    colorScheme == .dark
      ? Color.white.opacity(0.05)
      : Color.black.opacity(0.02)
  }

  private var oauthBorderColor: Color {
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

  private var continueButtonColor: Color {
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
      if !Task.isCancelled {
        errorMessage = error.localizedDescription
      }
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
      if !Task.isCancelled {
        errorMessage = error.localizedDescription
      }
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
        identifier: email,
        password: password
      )
      if signIn.status == .complete {
        dismiss()
      }
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  @MainActor
  private func signUpFlow() async {
    isLoading = true
    errorMessage = nil
    defer { isLoading = false }

    do {
      _ = try await Clerk.shared.auth.signInWithOAuth(provider: .google)
      dismiss()
    } catch {
      if !Task.isCancelled {
        errorMessage = error.localizedDescription
      }
    }
  }
}

// MARK: - Google Icon

private struct GoogleIcon: View {
  var body: some View {
    Canvas { context, size in
      let w = size.width
      let h = size.height
      let cx = w / 2
      let cy = h / 2
      let r = min(w, h) / 2 * 0.85

      // Blue (top-right arc)
      var bluePath = Path()
      bluePath.addArc(center: CGPoint(x: cx, y: cy), radius: r,
                      startAngle: .degrees(-30), endAngle: .degrees(-90),
                      clockwise: true)
      bluePath.addLine(to: CGPoint(x: cx, y: cy))
      bluePath.closeSubpath()
      context.fill(bluePath, with: .color(Color(red: 0.26, green: 0.52, blue: 0.96)))

      // Green (bottom-right arc)
      var greenPath = Path()
      greenPath.addArc(center: CGPoint(x: cx, y: cy), radius: r,
                       startAngle: .degrees(30), endAngle: .degrees(-30),
                       clockwise: true)
      greenPath.addLine(to: CGPoint(x: cx, y: cy))
      greenPath.closeSubpath()
      context.fill(greenPath, with: .color(Color(red: 0.2, green: 0.66, blue: 0.33)))

      // Yellow (bottom-left arc)
      var yellowPath = Path()
      yellowPath.addArc(center: CGPoint(x: cx, y: cy), radius: r,
                        startAngle: .degrees(150), endAngle: .degrees(30),
                        clockwise: true)
      yellowPath.addLine(to: CGPoint(x: cx, y: cy))
      yellowPath.closeSubpath()
      context.fill(yellowPath, with: .color(Color(red: 0.98, green: 0.74, blue: 0.02)))

      // Red (top-left arc)
      var redPath = Path()
      redPath.addArc(center: CGPoint(x: cx, y: cy), radius: r,
                     startAngle: .degrees(-90), endAngle: .degrees(150),
                     clockwise: true)
      redPath.addLine(to: CGPoint(x: cx, y: cy))
      redPath.closeSubpath()
      context.fill(redPath, with: .color(Color(red: 0.92, green: 0.26, blue: 0.21)))

      // White center
      let innerR = r * 0.55
      let whitePath = Path(ellipseIn: CGRect(
        x: cx - innerR, y: cy - innerR,
        width: innerR * 2, height: innerR * 2
      ))
      context.fill(whitePath, with: .color(.white))

      // Horizontal bar (the "G" opening)
      let barH = r * 0.22
      let barRect = CGRect(x: cx - r * 0.05, y: cy - barH / 2,
                           width: r * 1.0, height: barH)
      context.fill(Path(barRect), with: .color(Color(red: 0.26, green: 0.52, blue: 0.96)))
    }
    .frame(width: 18, height: 18)
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
