import SwiftUI

struct ContentToolbar<LeadingContent: View>: ViewModifier {
  let leadingContent: LeadingContent

  func body(content: Content) -> some View {
    content
      .toolbar {
        ToolbarItem { leadingContent }
      }
  }
}

extension View {
  func contentToolbar(
    @ViewBuilder leadingContent: () -> some View
  ) -> some View {
    modifier(
      ContentToolbar(
        leadingContent: leadingContent()
      ))
  }
}
