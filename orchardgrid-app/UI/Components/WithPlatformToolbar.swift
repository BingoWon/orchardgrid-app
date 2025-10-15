import SwiftUI

struct WithPlatformToolbar<LeadingContent: View>: ViewModifier {
  let leadingContent: LeadingContent

  func body(content: Content) -> some View {
    content
      .toolbar {
        // 只显示功能按钮（account 现在在 Sidebar/Tab Bar 中）
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

