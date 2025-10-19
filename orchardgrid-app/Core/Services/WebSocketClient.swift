/**
 * WebSocketClient.swift
 * OrchardGrid Device Client
 *
 * Connects to Cloudflare platform and processes LLM tasks
 */

import Foundation
@preconcurrency import FoundationModels
import Network
import OSLog

// MARK: - WebSocket Message Types
//
// All shared types are now defined in SharedTypes.swift
// This ensures proper type resolution by SourceKit and Swift compiler

// MARK: - WebSocket Client

@Observable
@MainActor
final class WebSocketClient: NSObject, URLSessionWebSocketDelegate {
  // Configuration
  private let serverURL: String
  private let deviceID: String
  private(set) var userID: String?
  private let platform: String
  private let osVersion: String

  // Connection state
  enum ConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case reconnecting(attempt: Int, nextRetryIn: TimeInterval?)
    case failed(String)
  }

  private(set) var connectionState: ConnectionState = .disconnected
  private(set) var tasksProcessed = 0

  // Computed properties for backward compatibility
  var isConnected: Bool {
    if case .connected = connectionState {
      return true
    }
    return false
  }

  var lastError: String? {
    if case let .failed(error) = connectionState {
      return error
    }
    return nil
  }

  // Model availability
  var modelAvailability: SystemLanguageModel.Availability {
    llmProcessor.availability
  }

  var canEnable: Bool {
    llmProcessor.isAvailable
  }

  var isEnabled = false {
    didSet {
      guard oldValue != isEnabled else { return }
      UserDefaults.standard.set(isEnabled, forKey: "WebSocketClient.isEnabled")
      if isEnabled {
        if userID != nil {
          // Cancel any existing reconnection tasks to avoid conflicts
          reconnectTask?.cancel()
          reconnectTask = nil
          retryTimerTask?.cancel()
          retryTimerTask = nil
          connect()
        }
      } else {
        disconnect()
      }
    }
  }

  // WebSocket
  private var webSocketTask: URLSessionWebSocketTask?
  private var urlSession: URLSession?
  private var shouldAutoReconnect = false
  private var reconnectTask: Task<Void, Never>?
  private var heartbeatTask: Task<Void, Never>?
  private var retryTimerTask: Task<Void, Never>?

  // Connection protection
  private var isConnecting = false

  // Network monitoring
  private let networkMonitor = NWPathMonitor()
  private var isNetworkAvailable = true

  // LLM Processing
  private let llmProcessor = LLMProcessor()

  // Heartbeat tracking
  private var lastHeartbeatResponse: Date?

  override init() {
    // Use Config.apiBaseURL and convert to WebSocket URL
    let httpURL = Config.apiBaseURL
    let wsURL = httpURL.replacingOccurrences(of: "https://", with: "wss://")
    let serverURL = ProcessInfo.processInfo.environment["ORCHARDGRID_SERVER_URL"]
      ?? "\(wsURL)/device/connect"
    let deviceID = DeviceID.current

    self.serverURL = serverURL
    self.deviceID = deviceID
    userID = nil // Will be set when connecting

    #if os(macOS)
      platform = "macOS"
    #elseif os(iOS)
      platform = "iOS"
    #else
      platform = "unknown"
    #endif

    osVersion = ProcessInfo.processInfo.operatingSystemVersionString

    // Restore previous state
    isEnabled = UserDefaults.standard.bool(forKey: "WebSocketClient.isEnabled")

    super.init()

    // Start network monitoring
    startNetworkMonitoring()
  }

  func setUserID(_ userID: String) {
    guard self.userID != userID else { return }
    self.userID = userID
    Logger.log(.websocket, "User ID set: \(userID)")
    // Auto-connect if enabled
    if isEnabled, !isConnected {
      connect()
    }
  }

  func retry() {
    Logger.log(.websocket, "User requested retry")
    // Cancel any existing reconnection tasks
    reconnectTask?.cancel()
    reconnectTask = nil
    retryTimerTask?.cancel()
    retryTimerTask = nil
    // Reset connecting flag
    isConnecting = false
    connectionState = .connecting
    connect()
  }

  deinit {
    // Stop network monitoring
    networkMonitor.cancel()
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

  // MARK: - Connection Management

  func connect() {
    // Prevent concurrent connections with atomic flag
    guard !isConnected, !isConnecting else {
      Logger.log(.websocket, "Already connected or connecting, skipping")
      return
    }

    guard let userID else {
      connectionState = .failed("User ID not set")
      Logger.error(.websocket, "Cannot connect: User ID not set")
      return
    }

    // Check network availability
    guard isNetworkAvailable else {
      Logger.log(.websocket, "Network unavailable, waiting for network...")
      connectionState = .disconnected
      return
    }

    Logger.log(.websocket, "Starting connection...")
    isConnecting = true
    connectionState = .connecting
    shouldAutoReconnect = true

    // Cancel any existing reconnection tasks
    reconnectTask?.cancel()
    reconnectTask = nil
    retryTimerTask?.cancel()
    retryTimerTask = nil

    // Create URL with device ID, user ID, platform, OS version, and hardware info
    guard var urlComponents = URLComponents(string: serverURL) else {
      isConnecting = false
      connectionState = .failed("Invalid server URL")
      return
    }
    urlComponents.queryItems = [
      URLQueryItem(name: "device_id", value: deviceID),
      URLQueryItem(name: "user_id", value: userID),
      URLQueryItem(name: "platform", value: platform),
      URLQueryItem(name: "os_version", value: osVersion),
      URLQueryItem(name: "device_name", value: DeviceInfo.deviceName),
      URLQueryItem(name: "chip_model", value: DeviceInfo.chipModel),
      URLQueryItem(
        name: "memory_gb",
        value: String(format: "%.0f", DeviceInfo.totalMemoryGB)
      ),
    ]

    guard let url = urlComponents.url else {
      isConnecting = false
      connectionState = .failed("Failed to construct URL")
      return
    }

    // Create URLSession with delegate
    let configuration = URLSessionConfiguration.default
    configuration.timeoutIntervalForRequest = 60 // Increased for WebSocket
    configuration.timeoutIntervalForResource = 0 // No limit for WebSocket
    configuration.waitsForConnectivity = true // Wait for network
    configuration.networkServiceType = .responsiveData // Responsive data
    urlSession = URLSession(
      configuration: configuration,
      delegate: self,
      delegateQueue: nil
    )

    // Create WebSocket task
    webSocketTask = urlSession?.webSocketTask(with: url)
    webSocketTask?.resume()

    Logger.log(.websocket, "Connecting to: \(url.absoluteString)")
    Logger.log(
      .websocket,
      "Device: \(deviceID), User: \(userID), Platform: \(platform), OS: \(osVersion)"
    )

    // Start receiving messages
    receiveMessage()
  }

  func disconnect() {
    Logger.log(.websocket, "Disconnecting...")
    shouldAutoReconnect = false
    isConnecting = false
    reconnectTask?.cancel()
    reconnectTask = nil
    retryTimerTask?.cancel()
    retryTimerTask = nil
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

          // Continue receiving
          self.receiveMessage()

        case let .failure(error):
          self.handleError(error)
        }
      }
    }
  }

  private func handleMessage(_ text: String) async {
    do {
      let data = text.data(using: .utf8)!

      // Try to decode as generic message to check type
      if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
         let type = json["type"] as? String
      {
        // Handle heartbeat response
        if type == "heartbeat" || type == "pong" {
          lastHeartbeatResponse = Date()
          Logger.log(.websocket, "Heartbeat response received")
          return
        }
      }

      // Create local decoder for thread-safe decoding
      let decoder = JSONDecoder()
      decoder.keyDecodingStrategy = .convertFromSnakeCase

      // Handle task message
      let taskMessage = try decoder.decode(TaskMessage.self, from: data)

      guard taskMessage.type == "task" else {
        Logger.log(.websocket, "Unknown message type: \(taskMessage.type)")
        return
      }

      Logger.log(.websocket, "Received task: \(taskMessage.id)")

      // Process task
      await processTask(taskMessage)

    } catch {
      Logger.error(.websocket, "Failed to decode message: \(error)")
      // Don't change connection state for message decode errors
    }
  }

  private func handleError(_ error: Error) {
    // Check if this is a cancellation error (Code=-999)
    let nsError = error as NSError
    if nsError.domain == NSURLErrorDomain, nsError.code == -999 {
      // Code=-999: Request cancelled
      // This is usually caused by concurrent connection attempts or system cancellation
      Logger.log(.websocket, "Connection cancelled (Code=-999)")
      // Reset connecting flag and don't change connection state
      isConnecting = false
      return
    }

    Logger.error(.websocket, "\(error)")
    isConnecting = false
    connectionState = .failed(error.localizedDescription)
    // Don't modify isEnabled - let user control it
  }

  // MARK: - Heartbeat

  private func startHeartbeat() {
    stopHeartbeat()

    heartbeatTask = Task { @MainActor in
      while !Task.isCancelled, isConnected {
        try? await Task.sleep(for: .seconds(DeviceConfig.heartbeatInterval))

        guard isConnected else { return }

        // Check for heartbeat timeout
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

        // Send heartbeat
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

        let wasAvailable = self.isNetworkAvailable
        self.isNetworkAvailable = path.status == .satisfied

        if !wasAvailable, self.isNetworkAvailable {
          // Network recovered
          Logger.log(.websocket, "Network recovered, attempting reconnection...")
          if self.shouldAutoReconnect, !self.isConnected, !self.isConnecting {
            // Cancel any existing reconnection task and start fresh
            self.reconnectTask?.cancel()
            self.reconnectTask = nil
            self.retryTimerTask?.cancel()
            self.retryTimerTask = nil
            self.connect()
          }
        } else if wasAvailable, !self.isNetworkAvailable {
          // Network lost
          Logger.log(.websocket, "Network lost, pausing reconnection...")
          // Cancel reconnection tasks when network is unavailable
          self.reconnectTask?.cancel()
          self.reconnectTask = nil
          self.retryTimerTask?.cancel()
          self.retryTimerTask = nil
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
        // Check network availability before attempting reconnection
        guard isNetworkAvailable else {
          Logger.log(.websocket, "Network unavailable, pausing reconnection...")
          return
        }

        attempts += 1

        // Update state with retry countdown
        connectionState = .reconnecting(attempt: attempts, nextRetryIn: delay)
        Logger.log(
          .websocket,
          "Reconnection attempt \(attempts) in \(String(format: "%.1f", delay))s..."
        )

        // Countdown timer (wait before next attempt)
        await startRetryCountdown(delay)

        guard !Task.isCancelled, shouldAutoReconnect, !isConnected, isNetworkAvailable else {
          Logger.log(.websocket, "Reconnection cancelled")
          return
        }

        // Reconnect
        connectionState = .connecting
        cleanupConnection()
        try? await Task.sleep(for: .seconds(0.5))
        connect()

        // Wait for connection result (delegate callbacks will update connectionState)
        // Use a shorter timeout to detect failures faster
        try? await Task.sleep(for: .seconds(5))

        if isConnected {
          Logger.success(.websocket, "Reconnected after \(attempts) attempts")
          return
        }

        // Two-phase backoff strategy:
        // Phase 1 (attempts 1-10): Fast reconnection (1s → 60s)
        // Phase 2 (attempts 11+): Slow reconnection (5 minutes)
        if attempts < 10 {
          delay = min(delay * 2, 60) // Exponential backoff, max 60s
        } else {
          delay = 300 // 5 minutes for long-term disconnection
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
        // Streaming response
        try await generateStreamingResponse(for: request, taskId: taskMessage.id)
      } else {
        // Complete response
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

    // Extract system prompt
    let systemPrompt = request.messages.first(where: { $0.role == "system" })?.content
      ?? DeviceConfig.defaultSystemPrompt

    // Filter out system messages
    let conversationMessages = request.messages.filter { $0.role != "system" }

    // Process request with streaming
    _ = try await llmProcessor.processRequest(
      messages: conversationMessages,
      systemPrompt: systemPrompt,
      responseFormat: request.response_format
    ) { [weak self] delta in
      Task {
        let chunkMessage = StreamChunkMessage(
          id: taskId,
          type: "stream",
          delta: delta
        )
        await self?.sendMessage(chunkMessage)
      }
    }

    // Send stream end
    let endMessage = StreamEndMessage(
      id: taskId,
      type: "stream_end"
    )
    await sendMessage(endMessage)
  }

  private func generateResponse(for request: ChatRequest) async throws -> ChatResponse {
    // Extract system prompt
    let systemPrompt = request.messages.first(where: { $0.role == "system" })?.content
      ?? DeviceConfig.defaultSystemPrompt

    // Filter out system messages
    let conversationMessages = request.messages.filter { $0.role != "system" }

    // Generate response
    let content = try await llmProcessor.processRequest(
      messages: conversationMessages,
      systemPrompt: systemPrompt,
      responseFormat: request.response_format
    )

    // Build OpenAI-compatible response
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
    // Rough estimation: ~4 characters per token
    let totalChars = messages.reduce(0) { $0 + $1.content.count }
    return max(1, totalChars / 4)
  }

  // MARK: - Message Sending

  private func sendMessage(_ message: some Encodable) async {
    do {
      // Create local encoder for thread-safe encoding
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
      // Don't change connection state for send errors
    }
  }
}
