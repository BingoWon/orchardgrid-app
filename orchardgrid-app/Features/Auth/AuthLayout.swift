/**
 * AuthLayout.swift
 * Shared layout for authentication screens
 */

import SwiftUI

struct AuthLayout<Content: View>: View {
  let content: Content

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    GeometryReader { geometry in
      ScrollView {
        VStack {
          content
        }
        .frame(maxWidth: 400) // Content width limit
        .padding(.horizontal, 24)
        .padding(.vertical, 40)
        .frame(minHeight: geometry.size.height) // Ensure full height for vertical centering if needed
      }
      .frame(maxWidth: .infinity) // ScrollView takes full width for better touch targets
      #if os(macOS)
      .frame(minWidth: 360, minHeight: 600)
      #endif
    }
  }
}

#Preview {
  AuthLayout {
    Text("Content goes here")
    AuthButton(title: "Action", isEnabled: true) {}
  }
}

