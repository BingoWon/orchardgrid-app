import SwiftUI

struct WithPlatformToolbar<LeadingContent: View>: ViewModifier {
  @Binding var showAccountSheet: Bool
  let leadingContent: LeadingContent

  func body(content: Content) -> some View {
    content
      .toolbar {
        #if os(macOS)
          // macOS: 显示功能按钮和 account 按钮
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
        #else
          if UIDevice.current.userInterfaceIdiom == .phone {
            // iPhone: 只显示功能按钮（account 在 Tab Bar）
            ToolbarItem { leadingContent }
          } else {
            // iPad: 显示功能按钮和 account 按钮
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
        #endif
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
  func withPlatformToolbar(
    showAccountSheet: Binding<Bool>,
    @ViewBuilder leadingContent: () -> some View
  ) -> some View {
    modifier(WithPlatformToolbar(
      showAccountSheet: showAccountSheet,
      leadingContent: leadingContent()
    ))
  }
}

