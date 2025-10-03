import SwiftUI

@main
struct OrchardGridApp: App {
  @State private var authManager: AuthManager
  @State private var wsClient: WebSocketClient
  @State private var apiServer = APIServer()
  @State private var devicesManager = DevicesManager()
  @Environment(\.scenePhase) private var scenePhase

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
    .onChange(of: scenePhase) { _, newPhase in
      handleScenePhaseChange(newPhase)
    }
  }

  private func handleScenePhaseChange(_ phase: ScenePhase) {
    switch phase {
    case .active:
      Logger.log(.app, "App became active")
      // Auto-reconnect if enabled and not connected
      if wsClient.isEnabled, !wsClient.isConnected, wsClient.userID != nil {
        Logger.log(.app, "Auto-reconnecting on app activation...")
        wsClient.connect()
      }
    case .inactive:
      Logger.log(.app, "App became inactive")
    case .background:
      Logger.log(.app, "App entered background")
    @unknown default:
      break
    }
  }
}
