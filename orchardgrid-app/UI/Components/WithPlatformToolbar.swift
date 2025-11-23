import SwiftUI

struct WithPlatformToolbar<LeadingContent: View>: ViewModifier {
  let leadingContent: LeadingContent

  func body(content: Content) -> some View {
    content
      .toolbar {
        // Only show functional buttons (account lives in Sidebar/Tab Bar)
        ToolbarItem { leadingContent }
      }
  }
}

extension View {
  func withPlatformToolbar(
    @ViewBuilder leadingContent: () -> some View
  ) -> some View {
    modifier(WithPlatformToolbar(
      leadingContent: leadingContent()
    ))
  }
}
