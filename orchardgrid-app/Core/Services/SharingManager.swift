/**
 * SharingManager.swift
 * OrchardGrid Unified Sharing State Management
 *
 * Single source of truth for:
 * - Apple Intelligence availability
 * - User sharing preferences (cloud/local)
 * - Service lifecycle coordination
 */

import Foundation
@preconcurrency import FoundationModels

@Observable
@MainActor
final class SharingManager {
  // MARK: - Core Services

  let llmProcessor = LLMProcessor()
  let cloudService: WebSocketClient
  let localService: APIServer

  // MARK: - Model Availability

  var modelAvailability: SystemLanguageModel.Availability {
    llmProcessor.availability
  }

  var isModelAvailable: Bool {
    llmProcessor.isAvailable
  }

  var isImageAvailable: Bool {
    ImageProcessor.isAvailable
  }

  // MARK: - User Intent (Persisted)

  private enum Keys {
    static let cloud = "SharingManager.cloudEnabled"
    static let local = "SharingManager.localEnabled"
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
    // Load persisted intent
    let wantsCloud = UserDefaults.standard.bool(forKey: Keys.cloud)
    let wantsLocal = UserDefaults.standard.bool(forKey: Keys.local)

    wantsCloudSharing = wantsCloud
    wantsLocalSharing = wantsLocal

    // Create services with shared processor
    cloudService = WebSocketClient(llmProcessor: llmProcessor)
    localService = APIServer(llmProcessor: llmProcessor)

    // Sync initial state
    syncAllStates()
  }

  // MARK: - Public API

  func setCloudSharing(_ enabled: Bool) {
    wantsCloudSharing = enabled
  }

  func setLocalSharing(_ enabled: Bool) {
    wantsLocalSharing = enabled
  }

  func retryCloudConnection() {
    cloudService.retry()
  }

  func setUserID(_ userID: String) {
    cloudService.setUserID(userID)
  }

  func clearUserID() {
    cloudService.clearUserID()
  }

  func refreshAvailability() {
    syncAllStates()
  }

  // MARK: - State Sync

  private func syncAllStates() {
    syncCloudState()
    syncLocalState()
  }

  private func syncCloudState() {
    cloudService.isEnabled = wantsCloudSharing && isModelAvailable
  }

  private func syncLocalState() {
    localService.isEnabled = wantsLocalSharing && isModelAvailable
  }
}
