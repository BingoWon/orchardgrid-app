/**
 * ObserverClient.swift
 * OrchardGrid Real-time Observer
 *
 * Subscribes to WebSocket events for real-time data updates
 */

import Foundation
import OSLog

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
  enum ConnectionStatus {
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
  private var pingTask: Task<Void, Never>?
  private var reconnectTask: Task<Void, Never>?
  private var authToken: String?

  override init() {
    super.init()
  }

  func connect(authToken: String) {
    guard status == .disconnected else { return }

    self.authToken = authToken
    status = .connecting

    // Build WebSocket URL
    let httpURL = Config.apiBaseURL
    let wsURL = httpURL.replacingOccurrences(of: "https://", with: "wss://")
      .replacingOccurrences(of: "http://", with: "ws://")
    let observeURL = "\(wsURL)/observe?token=\(authToken)"

    guard let url = URL(string: observeURL) else {
      Logger.error(.observer, "Invalid observer URL")
      status = .disconnected
      return
    }

    Logger.log(.observer, "Connecting to observer...")

    let configuration = URLSessionConfiguration.default
    configuration.timeoutIntervalForRequest = 60
    urlSession = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)

    webSocketTask = urlSession?.webSocketTask(with: url)
    webSocketTask?.resume()

    receiveMessage()
    startPing()
  }

  func disconnect() {
    Logger.log(.observer, "Disconnecting...")
    pingTask?.cancel()
    pingTask = nil
    reconnectTask?.cancel()
    reconnectTask = nil
    webSocketTask?.cancel(with: .goingAway, reason: nil)
    webSocketTask = nil
    urlSession?.invalidateAndCancel()
    urlSession = nil
    status = .disconnected
  }

  // MARK: - URLSessionWebSocketDelegate

  nonisolated func urlSession(
    _: URLSession,
    webSocketTask _: URLSessionWebSocketTask,
    didOpenWithProtocol _: String?
  ) {
    Task { @MainActor in
      Logger.success(.observer, "Connected")
      status = .connected
    }
  }

  nonisolated func urlSession(
    _: URLSession,
    webSocketTask _: URLSessionWebSocketTask,
    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
    reason _: Data?
  ) {
    Task { @MainActor in
      Logger.log(.observer, "Disconnected (code: \(closeCode.rawValue))")
      status = .disconnected
      scheduleReconnect()
    }
  }

  // MARK: - Private

  private func receiveMessage() {
    webSocketTask?.receive { [weak self] result in
      guard let self else { return }

      Task { @MainActor in
        switch result {
        case let .success(message):
          self.processMessage(message)
          self.receiveMessage()

        case let .failure(error):
          Logger.error(.observer, "Receive error: \(error.localizedDescription)")
          self.status = .disconnected
          self.scheduleReconnect()
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
      // Ignore unknown events
      Logger.log(.observer, "Unknown event received")
    }
  }

  private func handleEvent(_ event: ObserverEvent) {
    switch event {
    case .deviceOnline, .deviceOffline:
      Logger.log(.observer, "Device event received")
      onDevicesChanged?()

    case .deviceHeartbeat:
      // Heartbeat only updates timestamp, UI calculates relative time locally
      break

    case .taskCompleted, .taskFailed:
      Logger.log(.observer, "Task event received")
      onTasksChanged?()
      onDevicesChanged?() // Tasks affect device stats

    case .pong:
      break

    case .unknown:
      break
    }
  }

  private func startPing() {
    pingTask = Task { @MainActor in
      while !Task.isCancelled {
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

  private func scheduleReconnect() {
    guard reconnectTask == nil, let authToken else { return }

    reconnectTask = Task { @MainActor in
      try? await Task.sleep(for: .seconds(3))
      guard !Task.isCancelled else { return }
      self.reconnectTask = nil
      self.connect(authToken: authToken)
    }
  }
}
