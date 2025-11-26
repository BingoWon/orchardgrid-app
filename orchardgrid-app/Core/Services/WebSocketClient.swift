/**
 * WebSocketClient.swift
 * OrchardGrid Device Client
 *
 * Connects to Cloudflare platform and processes LLM tasks
 * Note: Lifecycle managed by SharingManager
 */

import Foundation
@preconcurrency import FoundationModels
import Network
import OSLog

@Observable
@MainActor
final class WebSocketClient: NSObject, URLSessionWebSocketDelegate {
  // MARK: - Configuration

  private let serverURL: String
  private let hardwareID: String
  private(set) var userID: String?
  private let platform: String
  private let osVersion: String

  // MARK: - Connection State

  enum ConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case reconnecting(attempt: Int, nextRetryIn: TimeInterval?)
    case failed(String)
  }

  private(set) var connectionState: ConnectionState = .disconnected
  private(set) var tasksProcessed = 0

  var isConnected: Bool {
    if case .connected = connectionState { return true }
    return false
  }

  var lastError: String? {
    if case let .failed(error) = connectionState { return error }
    return nil
  }

  // MARK: - Enabled State (Managed by SharingManager)

  var isEnabled = false {
    didSet {
      guard oldValue != isEnabled else { return }
      if isEnabled {
        reconnectTask?.cancel()
        reconnectTask = nil
        retryTimerTask?.cancel()
        retryTimerTask = nil
        connect()
      } else {
        disconnect()
      }
    }
  }

  // MARK: - Private State

  private var webSocketTask: URLSessionWebSocketTask?
  private var urlSession: URLSession?
  private var shouldAutoReconnect = false
  private var reconnectTask: Task<Void, Never>?
  private var heartbeatTask: Task<Void, Never>?
  private var retryTimerTask: Task<Void, Never>?
  private var connectionTimeoutTask: Task<Void, Never>?
  private var isConnecting = false
  private let networkMonitor = NWPathMonitor()
  private var isNetworkAvailable = true
  private var lastHeartbeatResponse: Date?

  // MARK: - Injected Dependencies

  private let llmProcessor: LLMProcessor

  // MARK: - Initialization

  init(llmProcessor: LLMProcessor) {
    self.llmProcessor = llmProcessor

    let httpURL = Config.apiBaseURL
    let wsURL = httpURL.replacingOccurrences(of: "https://", with: "wss://")
    serverURL = ProcessInfo.processInfo.environment["ORCHARDGRID_SERVER_URL"]
      ?? "\(wsURL)/device/connect"

    hardwareID = DeviceID.current
    userID = nil

    #if os(macOS)
      platform = "macOS"
    #elseif os(iOS)
      platform = "iOS"
    #else
      platform = "unknown"
    #endif

    osVersion = ProcessInfo.processInfo.operatingSystemVersionString

    super.init()
    startNetworkMonitoring()
  }

  deinit {
    networkMonitor.cancel()
  }

  // MARK: - Public API

  func setUserID(_ userID: String) {
    guard self.userID != userID else { return }
    self.userID = userID
    Logger.log(.websocket, "User ID updated: \(userID)")

    guard isEnabled else { return }

    if isConnected {
      // Reconnect to update user identity on server
      Logger.log(.websocket, "Reconnecting with new user identity...")
      disconnect()
    }
    connect()
  }

  func clearUserID() {
    guard userID != nil else { return }
    Logger.log(.websocket, "User ID cleared")
    userID = nil

    guard isEnabled, isConnected else { return }

    // Reconnect as anonymous
    Logger.log(.websocket, "Reconnecting as anonymous...")
    disconnect()
    connect()
  }

  func retry() {
    Logger.log(.websocket, "User requested retry")
    reconnectTask?.cancel()
    reconnectTask = nil
    retryTimerTask?.cancel()
    retryTimerTask = nil
    isConnecting = false
    connectionState = .connecting
    connect()
  }

  // MARK: - URLSessionWebSocketDelegate

  nonisolated func urlSession(
    _: URLSession,
    webSocketTask _: URLSessionWebSocketTask,
    didOpenWithProtocol _: String?
  ) {
    Task { @MainActor in
      isConnecting = false
      connectionState = .connected
      lastHeartbeatResponse = Date()
      reconnectTask?.cancel()
      reconnectTask = nil
      retryTimerTask?.cancel()
      retryTimerTask = nil
      connectionTimeoutTask?.cancel()
      connectionTimeoutTask = nil
      startHeartbeat()
      Logger.success(.websocket, "Connected")
    }
  }

  nonisolated func urlSession(
    _: URLSession,
    webSocketTask _: URLSessionWebSocketTask,
    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
    reason _: Data?
  ) {
    Task { @MainActor in
      isConnecting = false
      connectionState = .disconnected
      stopHeartbeat()
      Logger.log(.websocket, "Closed: \(closeCode.rawValue)")
      if shouldAutoReconnect, isNetworkAvailable {
        startReconnection()
      }
    }
  }

  nonisolated func urlSession(
    _: URLSession,
    task: URLSessionTask,
    didCompleteWithError error: Error?
  ) {
    Task { @MainActor in
      guard let error else { return }
      guard task is URLSessionWebSocketTask else { return }

      let nsError = error as NSError
      switch (nsError.domain, nsError.code) {
      case (NSPOSIXErrorDomain, 57):
        Logger.error(.websocket, "Connection failed: Socket not connected")
        isConnecting = false
        connectionState = .failed("Connection failed")
        if shouldAutoReconnect, isNetworkAvailable {
          startReconnection()
        }
      case (NSURLErrorDomain, -999):
        Logger.log(.websocket, "Connection cancelled")
        isConnecting = false
      default:
        Logger.error(.websocket, "Connection error: \(error.localizedDescription)")
        isConnecting = false
        connectionState = .failed(error.localizedDescription)
        if shouldAutoReconnect, isNetworkAvailable {
          startReconnection()
        }
      }
    }
  }

  // MARK: - Connection Management

  private func connect() {
    guard !isConnected, !isConnecting else {
      Logger.log(.websocket, "Already connected or connecting")
      return
    }

    guard isNetworkAvailable else {
      Logger.log(.websocket, "Network unavailable, waiting...")
      connectionState = .disconnected
      return
    }

    guard var urlComponents = URLComponents(string: serverURL) else {
      connectionState = .failed("Invalid server URL")
      Logger.error(.websocket, "Invalid server URL: \(serverURL)")
      return
    }

    guard urlComponents.scheme == "wss" || urlComponents.scheme == "ws" else {
      let scheme = urlComponents.scheme ?? "nil"
      connectionState = .failed("Invalid protocol: \(scheme)")
      Logger.error(.websocket, "WebSocket URL must use wss:// or ws://, got: \(scheme)")
      return
    }

    var queryItems = [
      URLQueryItem(name: "hardware_id", value: hardwareID),
      URLQueryItem(name: "platform", value: platform),
      URLQueryItem(name: "os_version", value: osVersion),
      URLQueryItem(name: "device_name", value: DeviceInfo.deviceName),
      URLQueryItem(name: "chip_model", value: DeviceInfo.chipModel),
      URLQueryItem(name: "memory_gb", value: String(format: "%.0f", DeviceInfo.totalMemoryGB)),
    ]
    if let userID {
      queryItems.append(URLQueryItem(name: "user_id", value: userID))
    }
    urlComponents.queryItems = queryItems

    guard let url = urlComponents.url else {
      connectionState = .failed("Failed to construct URL")
      Logger.error(.websocket, "Failed to construct URL from components")
      return
    }

    Logger.log(.websocket, "Connecting to: \(urlComponents.host ?? "unknown")")
    isConnecting = true
    connectionState = .connecting
    shouldAutoReconnect = true

    reconnectTask?.cancel()
    reconnectTask = nil
    retryTimerTask?.cancel()
    retryTimerTask = nil
    connectionTimeoutTask?.cancel()
    connectionTimeoutTask = nil

    let configuration = URLSessionConfiguration.default
    configuration.timeoutIntervalForRequest = DeviceConfig.connectionRequestTimeout
    configuration.timeoutIntervalForResource = 0
    configuration.waitsForConnectivity = true
    configuration.networkServiceType = .responsiveData
    urlSession = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)

    webSocketTask = urlSession?.webSocketTask(with: url)
    webSocketTask?.resume()
    receiveMessage()

    connectionTimeoutTask = Task { @MainActor in
      try? await Task.sleep(for: .seconds(DeviceConfig.connectionTimeout))
      if isConnecting, !isConnected {
        Logger.error(.websocket, "Connection timeout")
        isConnecting = false
        connectionState = .failed("Connection timeout")
        cleanupConnection()
        if shouldAutoReconnect, isNetworkAvailable {
          startReconnection()
        }
      }
    }
  }

  private func disconnect() {
    Logger.log(.websocket, "Disconnecting...")
    shouldAutoReconnect = false
    isConnecting = false
    reconnectTask?.cancel()
    reconnectTask = nil
    retryTimerTask?.cancel()
    retryTimerTask = nil
    connectionTimeoutTask?.cancel()
    connectionTimeoutTask = nil
    cleanupConnection()
    connectionState = .disconnected
    Logger.log(.websocket, "Disconnected")
  }

  private func cleanupConnection() {
    stopHeartbeat()
    webSocketTask?.cancel(with: .goingAway, reason: nil)
    webSocketTask = nil
    urlSession?.invalidateAndCancel()
    urlSession = nil
  }

  // MARK: - Message Handling

  private func receiveMessage() {
    guard shouldAutoReconnect || isConnected else { return }

    webSocketTask?.receive { [weak self] result in
      guard let self else { return }
      Task { @MainActor in
        switch result {
        case let .success(message):
          switch message {
          case let .string(text):
            await self.handleMessage(text)
          case let .data(data):
            if let text = String(data: data, encoding: .utf8) {
              await self.handleMessage(text)
            }
          @unknown default:
            break
          }
          if self.isConnected {
            self.receiveMessage()
          }
        case let .failure(error):
          if self.shouldAutoReconnect {
            Logger.error(.websocket, "Message receive error: \(error.localizedDescription)")
          }
        }
      }
    }
  }

  private func handleMessage(_ text: String) async {
    do {
      let data = text.data(using: .utf8)!

      if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
         let type = json["type"] as? String
      {
        if type == "heartbeat" || type == "pong" {
          lastHeartbeatResponse = Date()
          Logger.log(.websocket, "Heartbeat response received")
          return
        }
      }

      let decoder = JSONDecoder()
      decoder.keyDecodingStrategy = .convertFromSnakeCase
      let taskMessage = try decoder.decode(TaskMessage.self, from: data)

      guard taskMessage.type == "task" else {
        Logger.log(.websocket, "Unknown message type: \(taskMessage.type)")
        return
      }

      Logger.log(.websocket, "Received task: \(taskMessage.id)")
      await processTask(taskMessage)
    } catch {
      Logger.error(.websocket, "Failed to decode message: \(error)")
    }
  }

  // MARK: - Heartbeat

  private func startHeartbeat() {
    stopHeartbeat()
    heartbeatTask = Task { @MainActor in
      while !Task.isCancelled, isConnected {
        try? await Task.sleep(for: .seconds(DeviceConfig.heartbeatInterval))
        guard isConnected else { return }

        if let lastResponse = lastHeartbeatResponse,
           Date().timeIntervalSince(lastResponse) > DeviceConfig.heartbeatTimeout
        {
          Logger.error(.websocket, "Heartbeat timeout - connection appears dead")
          isConnecting = false
          connectionState = .disconnected
          stopHeartbeat()
          if shouldAutoReconnect, isNetworkAvailable {
            startReconnection()
          }
          return
        }

        let heartbeat = HeartbeatMessage(type: "heartbeat")
        await sendMessage(heartbeat)
        Logger.log(.websocket, "Heartbeat sent")
      }
    }
  }

  private func stopHeartbeat() {
    heartbeatTask?.cancel()
    heartbeatTask = nil
  }

  // MARK: - Network Monitoring

  private func startNetworkMonitoring() {
    networkMonitor.pathUpdateHandler = { [weak self] path in
      Task { @MainActor [weak self] in
        guard let self else { return }
        let wasAvailable = isNetworkAvailable
        isNetworkAvailable = path.status == .satisfied

        if !wasAvailable, isNetworkAvailable {
          Logger.log(.websocket, "Network recovered, attempting reconnection...")
          if shouldAutoReconnect, !isConnected, !isConnecting {
            reconnectTask?.cancel()
            reconnectTask = nil
            retryTimerTask?.cancel()
            retryTimerTask = nil
            connect()
          }
        } else if wasAvailable, !isNetworkAvailable {
          Logger.log(.websocket, "Network lost, pausing reconnection...")
          reconnectTask?.cancel()
          reconnectTask = nil
          retryTimerTask?.cancel()
          retryTimerTask = nil
        }
      }
    }
    networkMonitor.start(queue: .global(qos: .utility))
  }

  // MARK: - Reconnection

  private func startReconnection() {
    reconnectTask?.cancel()
    retryTimerTask?.cancel()

    reconnectTask = Task { @MainActor in
      var delay = 1.0
      var attempts = 0

      while !isConnected, shouldAutoReconnect, !Task.isCancelled {
        guard isNetworkAvailable else {
          Logger.log(.websocket, "Network unavailable, pausing reconnection...")
          return
        }

        attempts += 1
        connectionState = .reconnecting(attempt: attempts, nextRetryIn: delay)
        Logger.log(
          .websocket,
          "Reconnection attempt \(attempts) in \(String(format: "%.1f", delay))s..."
        )

        await startRetryCountdown(delay)

        guard !Task.isCancelled, shouldAutoReconnect, !isConnected, isNetworkAvailable else {
          Logger.log(.websocket, "Reconnection cancelled")
          return
        }

        connectionState = .connecting
        cleanupConnection()
        try? await Task.sleep(for: .seconds(0.5))
        connect()
        try? await Task.sleep(for: .seconds(DeviceConfig.reconnectionCheckInterval))

        if isConnected {
          Logger.success(.websocket, "Reconnected after \(attempts) attempts")
          return
        }

        if attempts < 10 {
          delay = min(delay * 2, 60)
        } else {
          delay = 300
        }
      }
    }
  }

  private func startRetryCountdown(_ totalSeconds: TimeInterval) async {
    retryTimerTask?.cancel()
    retryTimerTask = Task { @MainActor in
      var remaining = totalSeconds
      while remaining > 0, !Task.isCancelled {
        if case let .reconnecting(attempt, _) = connectionState {
          connectionState = .reconnecting(attempt: attempt, nextRetryIn: remaining)
        }
        try? await Task.sleep(for: .seconds(1))
        remaining -= 1
      }
    }
    await retryTimerTask?.value
  }

  // MARK: - Task Processing

  private func processTask(_ taskMessage: TaskMessage) async {
    let startTime = Date()
    let request = taskMessage.payload

    do {
      if request.stream == true {
        try await generateStreamingResponse(for: request, taskId: taskMessage.id)
      } else {
        let response = try await generateResponse(for: request)
        let responseMessage = ResponseMessage(
          id: taskMessage.id,
          type: "response",
          payload: response
        )
        await sendMessage(responseMessage)
      }

      tasksProcessed += 1
      let duration = Date().timeIntervalSince(startTime)
      Logger.success(.websocket, "Task completed in \(String(format: "%.2f", duration))s")
    } catch {
      Logger.error(.websocket, "Task failed: \(error)")
      let errorMessage = ErrorMessage(
        id: taskMessage.id,
        type: "error",
        error: error.localizedDescription
      )
      await sendMessage(errorMessage)
    }
  }

  private func generateStreamingResponse(for request: ChatRequest, taskId: String) async throws {
    Logger.log(.websocket, "Starting streaming response for task: \(taskId)")

    let systemPrompt = request.messages.first(where: { $0.role == "system" })?.content
      ?? LLMConfig.defaultSystemPrompt
    let conversationMessages = request.messages.filter { $0.role != "system" }

    _ = try await llmProcessor.processRequest(
      messages: conversationMessages,
      systemPrompt: systemPrompt,
      responseFormat: request.response_format
    ) { [weak self] delta in
      Task {
        let chunkMessage = StreamChunkMessage(id: taskId, type: "stream", delta: delta)
        await self?.sendMessage(chunkMessage)
      }
    }

    let endMessage = StreamEndMessage(id: taskId, type: "stream_end")
    await sendMessage(endMessage)
  }

  private func generateResponse(for request: ChatRequest) async throws -> ChatResponse {
    let systemPrompt = request.messages.first(where: { $0.role == "system" })?.content
      ?? LLMConfig.defaultSystemPrompt
    let conversationMessages = request.messages.filter { $0.role != "system" }

    let content = try await llmProcessor.processRequest(
      messages: conversationMessages,
      systemPrompt: systemPrompt,
      responseFormat: request.response_format
    )

    let id = "chatcmpl-\(UUID().uuidString.prefix(8))"
    let timestamp = Int(Date().timeIntervalSince1970)

    return ChatResponse(
      id: id,
      object: "chat.completion",
      created: timestamp,
      model: "apple-intelligence",
      choices: [
        ChatResponse.Choice(
          index: 0,
          message: ChatMessage(role: "assistant", content: content),
          finishReason: "stop"
        ),
      ],
      usage: ChatResponse.Usage(
        promptTokens: estimateTokens(request.messages),
        completionTokens: estimateTokens([ChatMessage(role: "assistant", content: content)]),
        totalTokens: estimateTokens(request.messages) + estimateTokens([ChatMessage(
          role: "assistant",
          content: content
        )])
      )
    )
  }

  private func estimateTokens(_ messages: [ChatMessage]) -> Int {
    let totalChars = messages.reduce(0) { $0 + $1.content.count }
    return max(1, totalChars / 4)
  }

  // MARK: - Message Sending

  private func sendMessage(_ message: some Encodable) async {
    do {
      let encoder = JSONEncoder()
      encoder.keyEncodingStrategy = .convertToSnakeCase
      let data = try encoder.encode(message)
      guard let text = String(data: data, encoding: .utf8) else {
        Logger.error(.websocket, "Failed to encode message as string")
        return
      }
      let wsMessage = URLSessionWebSocketTask.Message.string(text)
      try await webSocketTask?.send(wsMessage)
    } catch {
      Logger.error(.websocket, "Failed to send message: \(error)")
    }
  }
}
