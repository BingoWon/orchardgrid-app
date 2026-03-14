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

  private(set) var availabilityVersion = 0

  func isCapabilityAvailable(_ capability: Capability) -> Bool {
    _ = availabilityVersion
    return switch capability {
    case .chat: llmProcessor.isAvailable
    case .image: ImageProcessor.isAvailable
    case .nlp: NLPProcessor.isAvailable
    case .vision: VisionProcessor.isAvailable
    case .speech: SpeechProcessor.isAvailable
    case .sound: SoundProcessor.isAvailable
    }
  }

  func capabilityUnavailabilityReason(_ capability: Capability) -> String? {
    switch capability {
    case .chat: isModelAvailable ? nil : "Apple Intelligence is not available."
    case .image: ImageProcessor.unavailabilityReason
    case .nlp: NLPProcessor.isAvailable ? nil : "Text analysis is not available on this device."
    case .vision: VisionProcessor.isAvailable ? nil : "Vision is not available on this device."
    case .speech: SpeechProcessor.unavailabilityReason
    case .sound: SoundProcessor.isAvailable ? nil : "Sound analysis is not available on this device."
    }
  }

  func capabilityNeedsSettingsRedirect(_ capability: Capability) -> Bool {
    switch capability {
    case .speech: SpeechProcessor.needsSettingsRedirect
    default: false
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
  var localErrorMessage: String? {
    let msg = localService.errorMessage
    return msg.isEmpty ? nil : msg
  }
  var localPortConflict: Bool { localService.portConflict }
  var localSuggestedPort: UInt16? { localService.suggestedPort }

  func setLocalPort(_ port: UInt16) {
    localService.setPort(port)
  }

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
    availabilityVersion += 1
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
