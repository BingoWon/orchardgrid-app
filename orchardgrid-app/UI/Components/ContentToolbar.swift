import SwiftUI

struct ContentToolbar<TrailingContent: View>: ViewModifier {
  let trailingContent: TrailingContent

  func body(content: Content) -> some View {
    content
      .toolbar {
        #if !os(macOS)
          ToolbarSpacer(.fixed, placement: .topBarTrailing)
        #endif
        ToolbarItem(placement: .confirmationAction) { trailingContent }
      }
  }
}

extension View {
  func contentToolbar(
    @ViewBuilder trailingContent: () -> some View
  ) -> some View {
    modifier(ContentToolbar(trailingContent: trailingContent()))
  }
}
