import SwiftUI

@main
struct OrchardGridApp: App {
  @State private var authManager: AuthManager
  @State private var wsClient: WebSocketClient
  @State private var apiServer = APIServer()
  @State private var devicesManager = DevicesManager()
  @State private var windowSize: CGSize = .zero
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
        switch authManager.authState {
        case .loading:
          VStack(spacing: 16) {
            ProgressView()
              .controlSize(.large)
            Text("Loading...")
              .font(.headline)
              .foregroundStyle(.secondary)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .authenticated:
          MainView()
            .environment(authManager)
            .environment(wsClient)
            .environment(apiServer)
            .environment(devicesManager)
            .onGeometryChange(for: CGSize.self) { geometry in
              geometry.size
            } action: {
              windowSize = $0
            }

        case .unauthenticated:
          LoginView()
            .environment(authManager)
        }
      }
      .frame(minWidth: 375.0, minHeight: 375.0)
    }
    #if os(macOS)
    .commands {
      SidebarCommands() // Enable standard View menu commands for Sidebar toggling
    }
    #endif
    .onChange(of: scenePhase) { _, newPhase in
      handleScenePhaseChange(newPhase)
    }
  }

  private func handleScenePhaseChange(_ phase: ScenePhase) {
    switch phase {
    case .active:
      Logger.log(.app, "App became active")
    // No need to manually call connect() here
    // startReconnection() already handles reconnection logic
    case .inactive:
      Logger.log(.app, "App became inactive")
    case .background:
      Logger.log(.app, "App entered background")
    // Don't pause reconnection - maintain aggressive connection strategy
    @unknown default:
      break
    }
  }
}
