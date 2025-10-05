import SwiftUI

struct WithAccountToolbar<LeadingContent: View>: ViewModifier {
  @Binding var showAccountSheet: Bool
  let leadingContent: LeadingContent

  func body(content: Content) -> some View {
    content
      .toolbar {
        ToolbarItem { leadingContent }

        ToolbarSpacer(.flexible)

        ToolbarItemGroup {
          Button {
            showAccountSheet = true
          } label: {
            Label("Account", systemImage: "person.circle")
              .labelStyle(.iconOnly)
          }
        }
      }
      .sheet(isPresented: $showAccountSheet) {
        NavigationStack {
          AccountView()
          #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
          #endif
            .toolbar {
              #if os(macOS)
                ToolbarItem(placement: .automatic) {
                  Button("Close") {
                    showAccountSheet = false
                  }
                }
              #else
                ToolbarItem(placement: .topBarTrailing) {
                  Button(role: .close) {
                    showAccountSheet = false
                  }
                }
              #endif
            }
        }
        #if !os(macOS)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #endif
      }
  }
}

extension View {
  func withAccountToolbar(
    showAccountSheet: Binding<Bool>,
    @ViewBuilder leadingContent: () -> some View
  ) -> some View {
    modifier(WithAccountToolbar(
      showAccountSheet: showAccountSheet,
      leadingContent: leadingContent()
    ))
  }
}
