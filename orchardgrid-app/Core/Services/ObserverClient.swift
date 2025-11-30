/**
 * ObserverClient.swift
 * OrchardGrid Real-time Observer
 *
 * Subscribes to WebSocket events for real-time data updates
 */

import Foundation

// MARK: - Observer Event Types

enum ObserverEvent: Decodable {
  case deviceOnline(DeviceSummary)
  case deviceOffline(deviceId: String)
  case deviceHeartbeat(deviceId: String, lastHeartbeat: Int)
  case taskCompleted(taskId: String, deviceId: String, duration: Int)
  case taskFailed(taskId: String, error: String)
  case pong
  case unknown

  struct DeviceSummary: Decodable {
    let id: String
    let platform: String
    let deviceName: String?
    let isOnline: Bool
    let lastHeartbeat: Int

    enum CodingKeys: String, CodingKey {
      case id, platform
      case deviceName
      case isOnline
      case lastHeartbeat
    }
  }

  private enum CodingKeys: String, CodingKey {
    case type, device, deviceId, lastHeartbeat, taskId, duration, error
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let type = try container.decode(String.self, forKey: .type)

    switch type {
    case "DEVICE_ONLINE":
      let device = try container.decode(DeviceSummary.self, forKey: .device)
      self = .deviceOnline(device)
    case "DEVICE_OFFLINE":
      let deviceId = try container.decode(String.self, forKey: .deviceId)
      self = .deviceOffline(deviceId: deviceId)
    case "DEVICE_HEARTBEAT":
      let deviceId = try container.decode(String.self, forKey: .deviceId)
      let lastHeartbeat = try container.decode(Int.self, forKey: .lastHeartbeat)
      self = .deviceHeartbeat(deviceId: deviceId, lastHeartbeat: lastHeartbeat)
    case "TASK_COMPLETED":
      let taskId = try container.decode(String.self, forKey: .taskId)
      let deviceId = try container.decode(String.self, forKey: .deviceId)
      let duration = try container.decode(Int.self, forKey: .duration)
      self = .taskCompleted(taskId: taskId, deviceId: deviceId, duration: duration)
    case "TASK_FAILED":
      let taskId = try container.decode(String.self, forKey: .taskId)
      let error = try container.decode(String.self, forKey: .error)
      self = .taskFailed(taskId: taskId, error: error)
    case "pong":
      self = .pong
    default:
      self = .unknown
    }
  }
}

// MARK: - Observer Client

@Observable
@MainActor
final class ObserverClient: NSObject, URLSessionWebSocketDelegate {
  enum ConnectionStatus: Equatable {
    case disconnected
    case connecting
    case connected
  }

  private(set) var status: ConnectionStatus = .disconnected

  // Callbacks for data refresh
  var onDevicesChanged: (() -> Void)?
  var onTasksChanged: (() -> Void)?

  private var webSocketTask: URLSessionWebSocketTask?
  private var urlSession: URLSession?
  private var connectionTask: Task<Void, Never>?
  private var pingTask: Task<Void, Never>?
  private var authToken: String?

  // MARK: - Public API

  func connect(authToken: String) {
    self.authToken = authToken
    startConnection()
  }

  func disconnect() {
    stopConnection()
    authToken = nil
  }

  // MARK: - Connection Lifecycle

  private func startConnection() {
    connectionTask?.cancel()
    connectionTask = Task { @MainActor in
      var attempt = 0
      var delay: TimeInterval = 1

      while !Task.isCancelled, authToken != nil {
        attempt += 1
        let success = await attemptConnect()

        if success {
          Logger.success(.observer, attempt > 1 ? "Reconnected after \(attempt) attempts" : "Connected")
          break
        }

        // Exponential backoff: 1, 2, 4, 8... max 30 seconds
        Logger.log(.observer, "Reconnection attempt \(attempt) in \(Int(delay))s...")
        try? await Task.sleep(for: .seconds(delay))
        delay = min(delay * 2, 30)
      }
    }
  }

  private func stopConnection() {
    connectionTask?.cancel()
    connectionTask = nil
    cleanupConnection()
    status = .disconnected
    Logger.log(.observer, "Disconnected")
  }

  private func attemptConnect() async -> Bool {
    guard !Task.isCancelled, let authToken else { return false }

    let observeURL = "\(Config.webSocketBaseURL)/observe?token=\(authToken)"

    guard let url = URL(string: observeURL) else {
      Logger.error(.observer, "Invalid observer URL")
      return false
    }

    Logger.log(.observer, "Connecting to observer...")
    status = .connecting

    cleanupConnection()

    let configuration = URLSessionConfiguration.default
    configuration.timeoutIntervalForRequest = 60
    configuration.timeoutIntervalForResource = 0
    configuration.waitsForConnectivity = true
    urlSession = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)

    webSocketTask = urlSession?.webSocketTask(with: url)
    webSocketTask?.resume()
    receiveMessage()

    // Wait for connection with timeout
    let deadline = Date().addingTimeInterval(30)
    while !Task.isCancelled, Date() < deadline {
      if status == .connected { return true }
      try? await Task.sleep(for: .milliseconds(100))
    }

    if status != .connected {
      Logger.error(.observer, "Connection timeout")
      cleanupConnection()
      status = .disconnected
    }

    return false
  }

  private func cleanupConnection() {
    stopPing()
    webSocketTask?.cancel(with: .goingAway, reason: nil)
    webSocketTask = nil
    urlSession?.invalidateAndCancel()
    urlSession = nil
  }

  // MARK: - URLSessionWebSocketDelegate

  nonisolated func urlSession(
    _: URLSession,
    webSocketTask _: URLSessionWebSocketTask,
    didOpenWithProtocol _: String?
  ) {
    Task { @MainActor in
      status = .connected
      startPing()
    }
  }

  nonisolated func urlSession(
    _: URLSession,
    webSocketTask _: URLSessionWebSocketTask,
    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
    reason _: Data?
  ) {
    Task { @MainActor in
      Logger.log(.observer, "Closed (code: \(closeCode.rawValue))")
      status = .disconnected
      stopPing()
      if authToken != nil {
        startConnection()
      }
    }
  }

  nonisolated func urlSession(
    _: URLSession,
    task: URLSessionTask,
    didCompleteWithError error: Error?
  ) {
    Task { @MainActor in
      guard let error, task is URLSessionWebSocketTask else { return }

      let nsError = error as NSError
      // Ignore cancelled errors - expected during cleanup
      if nsError.domain == NSURLErrorDomain, nsError.code == -999 { return }

      Logger.error(.observer, "Connection error: \(error.localizedDescription)")
    }
  }

  // MARK: - Message Handling

  private func receiveMessage() {
    webSocketTask?.receive { [weak self] result in
      guard let self else { return }

      Task { @MainActor in
        switch result {
        case let .success(message):
          self.processMessage(message)
          if self.status == .connected {
            self.receiveMessage()
          }

        case let .failure(error):
          let nsError = error as NSError
          // Ignore cancelled errors - expected during cleanup
          if !(nsError.domain == NSURLErrorDomain && nsError.code == -999) {
            Logger.error(.observer, "Receive error: \(error.localizedDescription)")
          }
        }
      }
    }
  }

  private func processMessage(_ message: URLSessionWebSocketTask.Message) {
    guard case let .string(text) = message,
          let data = text.data(using: .utf8)
    else { return }

    do {
      let event = try JSONDecoder().decode(ObserverEvent.self, from: data)
      handleEvent(event)
    } catch {
      // Ignore unknown events (like INIT)
      Logger.log(.observer, "Unknown event received")
    }
  }

  private func handleEvent(_ event: ObserverEvent) {
    switch event {
    case .deviceOnline, .deviceOffline:
      Logger.log(.observer, "Device event received")
      onDevicesChanged?()

    case .taskCompleted, .taskFailed:
      Logger.log(.observer, "Task event received")
      onTasksChanged?()
      onDevicesChanged?()

    case .deviceHeartbeat, .pong, .unknown:
      break
    }
  }

  // MARK: - Ping

  private func startPing() {
    stopPing()
    pingTask = Task { @MainActor in
      while !Task.isCancelled, status == .connected {
        try? await Task.sleep(for: .seconds(30))
        guard !Task.isCancelled, status == .connected else { break }

        do {
          let pingMessage = URLSessionWebSocketTask.Message.string(#"{"type":"ping"}"#)
          try await webSocketTask?.send(pingMessage)
        } catch {
          Logger.error(.observer, "Ping failed: \(error.localizedDescription)")
        }
      }
    }
  }

  private func stopPing() {
    pingTask?.cancel()
    pingTask = nil
  }
}
