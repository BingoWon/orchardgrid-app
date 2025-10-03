import SwiftUI

@main
struct OrchardGridApp: App {
  @State private var authManager: AuthManager
  @State private var wsClient: WebSocketClient
  @State private var apiServer = APIServer()
  @State private var devicesManager = DevicesManager()

  init() {
    // Create instances
    let wsClient = WebSocketClient()
    let authManager = AuthManager()

    // Set up callback
    authManager.onUserIDChanged = { userId in
      Logger.log(.app, "User authenticated: \(userId)")
      wsClient.setUserID(userId)
    }

    // Initialize @State properties
    _wsClient = State(initialValue: wsClient)
    _authManager = State(initialValue: authManager)
  }

  var body: some Scene {
    WindowGroup {
      Group {
        if authManager.isAuthenticated {
          MainView()
            .environment(authManager)
            .environment(wsClient)
            .environment(apiServer)
            .environment(devicesManager)
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
