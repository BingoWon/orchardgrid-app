/**
 * AuthComponents.swift
 * Shared UI components for authentication
 */

import AuthenticationServices
import SwiftUI

// MARK: - Header

struct AuthHeader: View {
  let title: String
  let subtitle: String

  var body: some View {
    VStack(spacing: 8) {
      Text(title)
        .font(.system(size: 28, weight: .bold, design: .rounded))

      Text(subtitle)
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
  }
}

// MARK: - Social Login Buttons

enum SocialProvider {
  case apple
  case google

  var name: String {
    switch self {
    case .apple: "Apple"
    case .google: "Google"
    }
  }

  var iconName: String {
    switch self {
    case .apple: "apple.logo"
    case .google: "g.circle.fill"
    }
  }
}

struct SocialLoginButton: View {
  let provider: SocialProvider
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 12) {
        Group {
          switch provider {
          case .apple:
            Image(systemName: "apple.logo")
              .font(.system(size: 18, weight: .medium))
          case .google:
            GoogleIcon()
          }
        }
        .frame(width: 20, height: 20)

        Text("Continue with \(provider.name)")
          .font(.system(size: 16, weight: .medium))
      }
      .foregroundStyle(.primary)
      .frame(maxWidth: .infinity)
      .frame(height: 50)
      .background(Color(.systemBackground))
      .clipShape(RoundedRectangle(cornerRadius: 12))
      .overlay(
        RoundedRectangle(cornerRadius: 12)
          .stroke(Color(.separator), lineWidth: 1)
      )
    }
    .buttonStyle(.plain)
  }
}

// MARK: - Google Icon

private struct GoogleIcon: View {
  var body: some View {
    Canvas { context, size in
      let rect = CGRect(origin: .zero, size: size)
      let center = CGPoint(x: rect.midX, y: rect.midY)
      let radius = min(size.width, size.height) / 2 * 0.9

      // Blue arc (top-right)
      var bluePath = Path()
      bluePath.addArc(
        center: center,
        radius: radius,
        startAngle: .degrees(-45),
        endAngle: .degrees(45),
        clockwise: false
      )
      bluePath.addLine(to: center)
      bluePath.closeSubpath()
      context.fill(bluePath, with: .color(Color(red: 66 / 255, green: 133 / 255, blue: 244 / 255)))

      // Green arc (bottom-right)
      var greenPath = Path()
      greenPath.addArc(
        center: center,
        radius: radius,
        startAngle: .degrees(45),
        endAngle: .degrees(135),
        clockwise: false
      )
      greenPath.addLine(to: center)
      greenPath.closeSubpath()
      context.fill(greenPath, with: .color(Color(red: 52 / 255, green: 168 / 255, blue: 83 / 255)))

      // Yellow arc (bottom-left)
      var yellowPath = Path()
      yellowPath.addArc(
        center: center,
        radius: radius,
        startAngle: .degrees(135),
        endAngle: .degrees(225),
        clockwise: false
      )
      yellowPath.addLine(to: center)
      yellowPath.closeSubpath()
      context.fill(yellowPath, with: .color(Color(red: 251 / 255, green: 188 / 255, blue: 5 / 255)))

      // Red arc (top-left)
      var redPath = Path()
      redPath.addArc(
        center: center,
        radius: radius,
        startAngle: .degrees(225),
        endAngle: .degrees(315),
        clockwise: false
      )
      redPath.addLine(to: center)
      redPath.closeSubpath()
      context.fill(redPath, with: .color(Color(red: 234 / 255, green: 67 / 255, blue: 53 / 255)))

      // White center
      let innerRadius = radius * 0.55
      var whitePath = Path()
      whitePath.addEllipse(in: CGRect(
        x: center.x - innerRadius,
        y: center.y - innerRadius,
        width: innerRadius * 2,
        height: innerRadius * 2
      ))
      context.fill(whitePath, with: .color(.white))

      // Blue notch (right side opening)
      let notchWidth = radius * 0.45
      let notchHeight = radius * 0.35
      var notchPath = Path()
      notchPath.addRect(CGRect(
        x: center.x,
        y: center.y - notchHeight / 2,
        width: notchWidth + radius * 0.5,
        height: notchHeight
      ))
      context.fill(notchPath, with: .color(Color(red: 66 / 255, green: 133 / 255, blue: 244 / 255)))
    }
    .frame(width: 18, height: 18)
  }
}

// MARK: - Apple Sign In Wrapper

struct AppleSignInButton: View {
  let onCompletion: (Result<ASAuthorization, Error>) -> Void

  var body: some View {
    SignInWithAppleButton(.continue) { request in
      request.requestedScopes = [.email, .fullName]
    } onCompletion: { result in
      onCompletion(result)
    }
    .signInWithAppleButtonStyle(.black)
    .frame(height: 0)
    .opacity(0)
    .allowsHitTesting(false)
  }
}

// MARK: - Text Field

struct AuthField: View {
  let placeholder: String
  @Binding var text: String
  var isSecure: Bool = false

  @State private var showPassword = false

  var body: some View {
    HStack(spacing: 12) {
      Group {
        if isSecure, !showPassword {
          SecureField(placeholder, text: $text)
        } else {
          TextField(placeholder, text: $text)
        }
      }
      #if os(iOS)
      .autocapitalization(.none)
      #endif

      if isSecure {
        Button {
          showPassword.toggle()
        } label: {
          Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
            .foregroundStyle(.tertiary)
        }
        .buttonStyle(.plain)
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 14)
    .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 12))
  }
}

// MARK: - Primary Button

struct AuthButton: View {
  let title: String
  let isEnabled: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Text(title)
        .font(.headline)
        .frame(maxWidth: .infinity)
        .frame(height: 50)
    }
    .buttonStyle(.borderedProminent)
    .disabled(!isEnabled)
  }
}

// MARK: - Divider

struct AuthDivider: View {
  let text: String

  var body: some View {
    HStack(spacing: 16) {
      Rectangle().fill(.tertiary).frame(height: 1)
      Text(text).font(.caption).foregroundStyle(.tertiary)
      Rectangle().fill(.tertiary).frame(height: 1)
    }
  }
}

// MARK: - Error Banner

struct AuthErrorBanner: View {
  let message: String

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: "exclamationmark.circle.fill")
      Text(message).font(.callout)
    }
    .foregroundStyle(.white)
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .frame(maxWidth: .infinity)
    .background(.red.gradient, in: RoundedRectangle(cornerRadius: 12))
  }
}

// MARK: - Footer Link

struct AuthLink: View {
  let text: String
  let linkText: String
  let action: () -> Void

  var body: some View {
    HStack(spacing: 4) {
      Text(text).foregroundStyle(.secondary)
      Button(linkText, action: action).fontWeight(.semibold)
    }
    .font(.callout)
  }
}
