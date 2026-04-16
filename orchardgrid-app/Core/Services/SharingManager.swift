import Foundation
@preconcurrency import FoundationModels
import OrchardGridCore

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
    case .chat:
      isModelAvailable
        ? nil : String(localized: "Apple Foundation Model is not available.")
    case .image: ImageProcessor.unavailabilityReason
    case .nlp:
      NLPProcessor.isAvailable
        ? nil : String(localized: "Text analysis is not available on this device.")
    case .vision:
      VisionProcessor.isAvailable
        ? nil : String(localized: "Vision is not available on this device.")
    case .speech: SpeechProcessor.unavailabilityReason
    case .sound:
      SoundProcessor.isAvailable
        ? nil : String(localized: "Sound analysis is not available on this device.")
    }
  }

  func capabilityNeedsSettingsRedirect(_ capability: Capability) -> Bool {
    switch capability {
    case .speech: SpeechProcessor.needsSettingsRedirect
    default: false
    }
  }

  // MARK: - User Intent (Persisted in App Group — readable by `og` CLI)

  private var defaults: UserDefaults { OGSharedDefaults.store }

  private(set) var wantsCloudSharing: Bool {
    didSet {
      guard oldValue != wantsCloudSharing else { return }
      defaults.set(wantsCloudSharing, forKey: OGSharedDefaults.Key.cloudEnabled)
      syncCloudState()
    }
  }

  /// Opt-in flag for the community pool. When false (default), the
  /// device only serves the owner's own requests even while
  /// cloud-shared. When true, any signed-in OrchardGrid user can
  /// dispatch to this device.
  private(set) var wantsPublicSharing: Bool {
    didSet {
      guard oldValue != wantsPublicSharing else { return }
      defaults.set(wantsPublicSharing, forKey: OGSharedDefaults.Key.cloudPublic)
      cloudService.updateShareScope(wantsPublicSharing ? .public : .private)
    }
  }

  private(set) var wantsLocalSharing: Bool {
    didSet {
      guard oldValue != wantsLocalSharing else { return }
      defaults.set(wantsLocalSharing, forKey: OGSharedDefaults.Key.localEnabled)
      syncLocalState()
    }
  }

  private(set) var enabledCapabilities: Set<Capability> {
    didSet {
      guard oldValue != enabledCapabilities else { return }
      defaults.set(
        enabledCapabilities.map(\.rawValue).joined(separator: ","),
        forKey: OGSharedDefaults.Key.enabledCapabilities)
      syncCapabilities()
    }
  }

  // MARK: - Service State (Computed)

  var isCloudActive: Bool { cloudService.isConnected }
  var isLocalActive: Bool { localService.isRunning }
  var isAnySharingActive: Bool { wantsCloudSharing || wantsLocalSharing }
  var cloudConnectionState: WebSocketClient.ConnectionState { cloudService.connectionState }
  var cloudLogsProcessed: Int { cloudService.logsProcessed }
  var localRequestCount: Int { localService.requestCount }
  var localPort: UInt16 { localService.port }
  var localIPAddress: String? { localService.localIPAddress }
  var localError: APIError? { localService.lastError }
  var localPortConflict: Bool { localService.portConflict }
  var localSuggestedPort: UInt16? { localService.suggestedPort }

  func setLocalPort(_ port: UInt16) {
    localService.setPort(port)
  }

  // MARK: - Initialization

  init() {
    let store = OGSharedDefaults.store
    let wantsCloud = store.bool(forKey: OGSharedDefaults.Key.cloudEnabled)
    let wantsPublic = store.bool(forKey: OGSharedDefaults.Key.cloudPublic)
    let wantsLocal = store.bool(forKey: OGSharedDefaults.Key.localEnabled)

    // Capabilities are stored as a comma-separated string in the App
    // Group (CLI reads this without needing CoreFoundation array decoding).
    if let raw = store.string(forKey: OGSharedDefaults.Key.enabledCapabilities) {
      enabledCapabilities = Set(
        raw.split(separator: ",").compactMap { Capability(rawValue: String($0)) })
    } else {
      enabledCapabilities = Set(Capability.allCases)
    }

    wantsCloudSharing = wantsCloud
    wantsPublicSharing = wantsPublic
    wantsLocalSharing = wantsLocal

    cloudService = WebSocketClient(
      llmProcessor: llmProcessor,
      shareScope: wantsPublic ? .public : .private)
    localService = APIServer(llmProcessor: llmProcessor)

    syncAllStates()
  }

  // MARK: - Public API

  func setCloudSharing(_ enabled: Bool) {
    wantsCloudSharing = enabled
  }

  func setPublicSharing(_ enabled: Bool) {
    wantsPublicSharing = enabled
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

  func reconnectCloudIfNeeded() {
    guard wantsCloudSharing, isModelAvailable,
      !cloudService.isConnected, cloudService.connectionState == .disconnected
    else { return }
    cloudService.retry()
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
