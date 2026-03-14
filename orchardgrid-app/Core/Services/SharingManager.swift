import Foundation
@preconcurrency import FoundationModels

@Observable
@MainActor
final class SharingManager {
  // MARK: - Core Services

  let llmProcessor = LLMProcessor()
  private let cloudService: WebSocketClient
  private let localService: APIServer

  // MARK: - Availability

  var modelAvailability: SystemLanguageModel.Availability {
    llmProcessor.availability
  }

  var isModelAvailable: Bool {
    llmProcessor.isAvailable
  }

  func isCapabilityAvailable(_ capability: Capability) -> Bool {
    switch capability {
    case .chat: llmProcessor.isAvailable
    case .image: ImageProcessor.isAvailable
    case .nlp: NLPProcessor.isAvailable
    case .vision: VisionProcessor.isAvailable
    case .speech: SpeechProcessor.isAvailable
    case .sound: SoundProcessor.isAvailable
    }
  }

  // MARK: - User Intent (Persisted)

  private enum Keys {
    static let cloud = "SharingManager.cloudEnabled"
    static let local = "SharingManager.localEnabled"
    static let enabledCapabilities = "SharingManager.enabledCapabilities"
  }

  private(set) var wantsCloudSharing: Bool {
    didSet {
      guard oldValue != wantsCloudSharing else { return }
      UserDefaults.standard.set(wantsCloudSharing, forKey: Keys.cloud)
      syncCloudState()
    }
  }

  private(set) var wantsLocalSharing: Bool {
    didSet {
      guard oldValue != wantsLocalSharing else { return }
      UserDefaults.standard.set(wantsLocalSharing, forKey: Keys.local)
      syncLocalState()
    }
  }

  private(set) var enabledCapabilities: Set<Capability> {
    didSet {
      guard oldValue != enabledCapabilities else { return }
      UserDefaults.standard.set(enabledCapabilities.map(\.rawValue), forKey: Keys.enabledCapabilities)
      syncCapabilities()
    }
  }

  // MARK: - Service State (Computed)

  var isCloudActive: Bool { cloudService.isConnected }
  var isLocalActive: Bool { localService.isRunning }
  var isAnySharingActive: Bool { wantsCloudSharing || wantsLocalSharing }
  var cloudConnectionState: WebSocketClient.ConnectionState { cloudService.connectionState }
  var cloudTasksProcessed: Int { cloudService.tasksProcessed }
  var localRequestCount: Int { localService.requestCount }
  var localPort: UInt16 { localService.port }
  var localIPAddress: String? { localService.localIPAddress }

  // MARK: - Initialization

  init() {
    let wantsCloud = UserDefaults.standard.bool(forKey: Keys.cloud)
    let wantsLocal = UserDefaults.standard.bool(forKey: Keys.local)

    if let saved = UserDefaults.standard.stringArray(forKey: Keys.enabledCapabilities) {
      enabledCapabilities = Set(saved.compactMap { Capability(rawValue: $0) })
    } else {
      enabledCapabilities = Set(Capability.allCases)
    }

    wantsCloudSharing = wantsCloud
    wantsLocalSharing = wantsLocal

    cloudService = WebSocketClient(llmProcessor: llmProcessor)
    localService = APIServer(llmProcessor: llmProcessor)

    syncAllStates()
  }

  // MARK: - Public API

  func setCloudSharing(_ enabled: Bool) {
    wantsCloudSharing = enabled
  }

  func setLocalSharing(_ enabled: Bool) {
    wantsLocalSharing = enabled
  }

  func setCapabilityEnabled(_ capability: Capability, enabled: Bool) {
    if enabled {
      enabledCapabilities.insert(capability)
    } else {
      enabledCapabilities.remove(capability)
    }
  }

  func isCapabilityEnabled(_ capability: Capability) -> Bool {
    enabledCapabilities.contains(capability)
  }

  func retryCloudConnection() {
    cloudService.retry()
  }

  func setAuth(tokenProvider: @escaping @Sendable () async -> String?) {
    cloudService.setAuth(tokenProvider: tokenProvider)
  }

  func clearAuth() {
    cloudService.clearAuth()
  }

  func refreshAvailability() {
    syncAllStates()
  }

  // MARK: - State Sync

  private func syncAllStates() {
    syncCapabilities()
    syncCloudState()
    syncLocalState()
  }

  private func syncCapabilities() {
    cloudService.updateEnabledCapabilities(enabledCapabilities)
    localService.updateEnabledCapabilities(enabledCapabilities)
  }

  private func syncCloudState() {
    cloudService.isEnabled = wantsCloudSharing && isModelAvailable
  }

  private func syncLocalState() {
    localService.isEnabled = wantsLocalSharing && isModelAvailable
  }
}
