import ClerkKit
import Speech
import SwiftUI

#if os(macOS)
  import AppKit
#elseif os(iOS)
  import UIKit
#endif

@main
struct OrchardGridApp: App {
  @State private var clerk: Clerk
  @State private var authManager: AuthManager
  @State private var sharingManager: SharingManager
  @State private var observerClient: ObserverClient
  @State private var backgroundManager = BackgroundManager()
  @State private var navigationState = NavigationState()
  @State private var devicesManager = DevicesManager()
  @State private var logsManager = LogsManager()
  @State private var chatManager = ChatManager()
  @Environment(\.scenePhase) private var scenePhase

  init() {
    Logger.log(.app, "OrchardGrid starting...")
    Logger.log(.app, "API: \(Config.apiBaseURL)")

    let clerk = Clerk.configure(publishableKey: Config.clerkPublishableKey)

    let sharingManager = SharingManager()
    let authManager = AuthManager()
    let observerClient = ObserverClient()

    authManager.onUserIDChanged = { _ in
      sharingManager.setAuth { await authManager.getToken() }
    }

    authManager.onLogout = {
      sharingManager.clearAuth()
      observerClient.disconnect()
    }

    _clerk = State(initialValue: clerk)
    _sharingManager = State(initialValue: sharingManager)
    _authManager = State(initialValue: authManager)
    _observerClient = State(initialValue: observerClient)

    Logger.success(.app, "Initialization complete")
  }

  var body: some Scene {
    WindowGroup {
      Group {
        if clerk.isLoaded {
          MainView()
            .environment(clerk)
            .environment(authManager)
            .environment(sharingManager)
            .environment(observerClient)
            .environment(backgroundManager)
            .environment(navigationState)
            .environment(devicesManager)
            .environment(logsManager)
            .environment(chatManager)
        } else {
          VStack(spacing: 16) {
            ProgressView()
              .controlSize(.large)
            Text("Loading...")
              .font(.headline)
              .foregroundStyle(.secondary)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
      }
      .frame(minWidth: 375.0, minHeight: 375.0)
      .task(id: clerk.user?.id) {
        guard clerk.isLoaded else { return }
        if let userId = clerk.user?.id {
          Logger.log(.app, "Auth sync: \(userId)")
          authManager.onUserIDChanged?(userId)
          connectObserver()
        } else {
          authManager.onLogout?()
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
        setupTerminationHandler()
        await requestPermissions()
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

  private func connectObserver() {
    observerClient.connect(tokenProvider: { await authManager.getToken() })
    observerClient.onDevicesChanged = { [devicesManager, authManager] in
      Task {
        guard let token = await authManager.getToken() else { return }
        await devicesManager.fetchDevices(authToken: token, isManualRefresh: false)
      }
    }
    observerClient.onTasksChanged = { [logsManager, authManager] in
      Task {
        guard let token = await authManager.getToken() else { return }
        await logsManager.reload(authToken: token, isManualRefresh: false)
      }
    }
  }

  private func requestPermissions() async {
    let speechGranted = await SpeechProcessor.requestPermissionIfNeeded()
    Logger.log(.app, "Speech recognition permission: \(speechGranted ? "granted" : "denied")")
    sharingManager.refreshAvailability()
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
      sharingManager.reconnectCloudIfNeeded()
      backgroundManager.handleEnterForeground()
      if authManager.isAuthenticated, observerClient.status == .disconnected {
        connectObserver()
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
