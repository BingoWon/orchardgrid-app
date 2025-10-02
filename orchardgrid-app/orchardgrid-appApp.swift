import SwiftUI

@main
struct OrchardGridApp: App {
  @State private var authManager = AuthManager()
  @State private var client = WebSocketClient()

  var body: some Scene {
    WindowGroup {
      Group {
        if authManager.isAuthenticated {
          DashboardView()
            .environment(authManager)
            .environment(client)
            .task {
              await client.connect()
            }
            .onDisappear {
              client.disconnect()
            }
        } else {
          LoginView()
            .environment(authManager)
        }
      }
    }
    .commands {
      CommandGroup(replacing: .newItem) {}
    }
  }
}
