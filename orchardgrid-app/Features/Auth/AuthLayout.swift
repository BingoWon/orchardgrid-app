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
    ScrollView {
      VStack {
        content
      }
      .frame(maxWidth: 400)
      .padding(.horizontal, 24)
      .padding(.vertical, 40)
    }
  }
}

#Preview {
  AuthLayout {
    Text("Content goes here")
    AuthButton(title: "Action", isEnabled: true) {}
  }
}
