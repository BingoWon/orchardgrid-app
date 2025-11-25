/**
 * AuthComponents.swift
 * Shared UI components for authentication
 */

import GoogleSignInSwift
import SwiftUI

// MARK: - Header

struct AuthHeader: View {
  let title: String
  let subtitle: String

  var body: some View {
    VStack(spacing: 12) {
      Image(systemName: "cpu.fill")
        .font(.system(size: 56))
        .foregroundStyle(.tint)

      Text(title)
        .font(.system(size: 32, weight: .bold, design: .rounded))

      Text(subtitle)
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
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

// MARK: - Google Button

struct GoogleButton: View {
  let action: () -> Void

  var body: some View {
    GoogleSignInButton(scheme: .dark, style: .wide, state: .normal) {
      action()
    }
    .frame(height: 50)
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
