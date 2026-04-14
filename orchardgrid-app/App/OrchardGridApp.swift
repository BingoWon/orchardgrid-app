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
  @State private var devicesManager: DevicesManager
  @State private var apiKeysManager: APIKeysManager
  @State private var logsManager: LogsManager
  @State private var chatManager = ChatManager()
  @Environment(\.scenePhase) private var scenePhase

  init() {
    Logger.log(.app, "OrchardGrid starting...")
    Logger.log(.app, "API: \(Config.apiBaseURL)")

    let clerk = Clerk.configure(publishableKey: Config.clerkPublishableKey)

    let tokenProvider: @Sendable () async -> String? = {
      try? await Clerk.shared.session?.getToken()
    }

    guard let baseURL = URL(string: Config.apiBaseURL) else {
      fatalError("Invalid API_BASE_URL: \(Config.apiBaseURL)")
    }
    let api = APIClient(baseURL: baseURL, tokenProvider: tokenProvider)

    let authManager = AuthManager(api: api)
    let sharingManager = SharingManager()
    let observerClient = ObserverClient()

    sharingManager.setAuth(tokenProvider: tokenProvider)

    authManager.onLogout = {
      sharingManager.clearAuth()
      observerClient.disconnect()
    }

    _clerk = State(initialValue: clerk)
    _sharingManager = State(initialValue: sharingManager)
    _authManager = State(initialValue: authManager)
    _observerClient = State(initialValue: observerClient)
    _devicesManager = State(initialValue: DevicesManager(api: api))
    _apiKeysManager = State(initialValue: APIKeysManager(api: api))
    _logsManager = State(initialValue: LogsManager(api: api))

    Logger.success(.app, "Initialization complete")
  }

  @AppStorage("AppAppearance") private var appAppearance = "system"

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
            .environment(apiKeysManager)
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
      .preferredColorScheme(AppAppearance.colorScheme(for: appAppearance))
      .frame(minWidth: 375.0, minHeight: 375.0)
      .task(id: clerk.user?.id) {
        guard clerk.isLoaded else { return }
        if clerk.user?.id != nil {
          Logger.log(.app, "Auth sync: \(clerk.user?.id ?? "?")")
          sharingManager.retryCloudConnection()
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
    observerClient.connect(
      tokenProvider: { try? await Clerk.shared.session?.getToken() })
    observerClient.onDevicesChanged = { [devicesManager] in
      Task { await devicesManager.fetchDevices() }
    }
    observerClient.onTasksChanged = { [logsManager] in
      Task { await logsManager.reload() }
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
