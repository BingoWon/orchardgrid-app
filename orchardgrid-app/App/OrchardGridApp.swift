import GoogleSignIn
import SwiftUI

@main
struct OrchardGridApp: App {
  @State private var authManager: AuthManager
  @State private var sharingManager: SharingManager
  @State private var observerClient: ObserverClient
  @State private var navigationState = NavigationState()
  @State private var devicesManager = DevicesManager()
  @State private var logsManager = LogsManager()
  @State private var windowSize: CGSize = .zero
  @Environment(\.scenePhase) private var scenePhase

  init() {
    Logger.log(.app, "OrchardGrid starting...")
    Logger.log(.app, "API: \(Config.apiBaseURL)")

    let sharingManager = SharingManager()
    let authManager = AuthManager()
    let observerClient = ObserverClient()

    authManager.onUserIDChanged = { userId in
      Logger.log(.app, "User authenticated: \(userId)")
      sharingManager.setUserID(userId)
    }

    authManager.onLogout = {
      Logger.log(.app, "User logged out, disconnecting...")
      sharingManager.clearUserID()
      observerClient.disconnect()
    }

    _sharingManager = State(initialValue: sharingManager)
    _authManager = State(initialValue: authManager)
    _observerClient = State(initialValue: observerClient)

    Logger.success(.app, "Initialization complete")
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

        case .authenticated, .guest:
          MainView()
            .environment(authManager)
            .environment(sharingManager)
            .environment(observerClient)
            .environment(navigationState)
            .environment(devicesManager)
            .environment(logsManager)
            .onGeometryChange(for: CGSize.self) { geometry in
              geometry.size
            } action: {
              windowSize = $0
            }
        }
      }
      .frame(minWidth: 375.0, minHeight: 375.0)
      .onChange(of: authManager.authToken) { oldToken, newToken in
        if let token = newToken {
          Logger.log(.app, "Auth token available, connecting observer...")
          observerClient.connect(authToken: token)
          setupObserverCallbacks()
        } else if oldToken != nil {
          Logger.log(.app, "Auth token removed, disconnecting observer...")
          observerClient.disconnect()
        }
      }
      .task {
        if let token = authManager.authToken {
          Logger.log(.app, "Initial auth token found, connecting observer...")
          observerClient.connect(authToken: token)
          setupObserverCallbacks()
        }
      }
    }
    #if os(macOS)
    .commands {
      SidebarCommands()
    }
    #endif
    .onChange(of: scenePhase) { _, newPhase in
      handleScenePhaseChange(newPhase)
    }
  }

  private func setupObserverCallbacks() {
    observerClient.onDevicesChanged = { [devicesManager, authManager] in
      Task {
        if let token = authManager.authToken {
          await devicesManager.fetchDevices(authToken: token, isManualRefresh: false)
        }
      }
    }

    observerClient.onTasksChanged = { [logsManager, authManager] in
      Task {
        if let token = authManager.authToken {
          await logsManager.reload(authToken: token, isManualRefresh: false)
        }
      }
    }
  }

  private func handleScenePhaseChange(_ phase: ScenePhase) {
    switch phase {
    case .active:
      Logger.log(.app, "App became active")
      // Refresh availability when app becomes active (user might have changed AI settings)
      sharingManager.refreshAvailability()
      // Reconnect observer if disconnected
      if let token = authManager.authToken, observerClient.status == .disconnected {
        observerClient.connect(authToken: token)
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
