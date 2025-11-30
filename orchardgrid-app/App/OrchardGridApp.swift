import GoogleSignIn
import SwiftUI

#if os(macOS)
  import AppKit
#elseif os(iOS)
  import UIKit
#endif

@main
struct OrchardGridApp: App {
  @State private var authManager: AuthManager
  @State private var sharingManager: SharingManager
  @State private var observerClient: ObserverClient
  @State private var backgroundManager = BackgroundManager()
  @State private var navigationState = NavigationState()
  @State private var devicesManager = DevicesManager()
  @State private var logsManager = LogsManager()
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
            .environment(backgroundManager)
            .environment(navigationState)
            .environment(devicesManager)
            .environment(logsManager)
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
      .onChange(of: sharingManager.isAnySharingActive) { _, isActive in
        if isActive {
          backgroundManager.enableBackgroundExecution()
        } else {
          backgroundManager.disableBackgroundExecution()
        }
      }
      .task {
        if let token = authManager.authToken {
          Logger.log(.app, "Initial auth token found, connecting observer...")
          observerClient.connect(authToken: token)
          setupObserverCallbacks()
        }
        setupTerminationHandler()
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

  private func setupTerminationHandler() {
    #if os(macOS)
      NotificationCenter.default.addObserver(
        forName: NSApplication.willTerminateNotification,
        object: nil,
        queue: .main
      ) { _ in
        Task { @MainActor in
          backgroundManager.prepareForTermination()
        }
      }
    #elseif os(iOS)
      NotificationCenter.default.addObserver(
        forName: UIApplication.willTerminateNotification,
        object: nil,
        queue: .main
      ) { _ in
        Task { @MainActor in
          backgroundManager.prepareForTermination()
        }
      }
    #endif
  }

  private func handleScenePhaseChange(_ phase: ScenePhase) {
    switch phase {
    case .active:
      Logger.log(.app, "App became active")
      sharingManager.refreshAvailability()
      backgroundManager.handleEnterForeground()
      if let token = authManager.authToken, observerClient.status == .disconnected {
        observerClient.connect(authToken: token)
      }
    case .inactive:
      Logger.log(.app, "App became inactive")
    case .background:
      Logger.log(.app, "App entered background")
      backgroundManager.handleEnterBackground()
    @unknown default:
      break
    }
  }
}
