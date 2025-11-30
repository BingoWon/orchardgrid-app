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
    case reconnecting(attempt: Int, nextRetryIn: TimeInterval)
    case failed(String)
  }

  private(set) var connectionState: ConnectionState = .disconnected
  private(set) var tasksProcessed = 0

  var isConnected: Bool {
    if case .connected = connectionState { return true }
    return false
  }

  // MARK: - Enabled State (Managed by SharingManager)

  var isEnabled = false {
    didSet {
      guard oldValue != isEnabled else { return }
      if isEnabled {
        startConnection()
      } else {
        stopConnection()
      }
    }
  }

  // MARK: - Private State

  private var webSocketTask: URLSessionWebSocketTask?
  private var urlSession: URLSession?
  private var connectionTask: Task<Void, Never>?
  private var heartbeatTask: Task<Void, Never>?
  private var isConnectionLoopActive = false
  private let networkMonitor = NWPathMonitor()
  private var isNetworkAvailable = true
  private var lastHeartbeatResponse: Date?

  // MARK: - Injected Dependencies

  private let llmProcessor: LLMProcessor

  // MARK: - Initialization

  init(llmProcessor: LLMProcessor) {
    self.llmProcessor = llmProcessor

    serverURL = ProcessInfo.processInfo.environment["ORCHARDGRID_SERVER_URL"]
      ?? "\(Config.webSocketBaseURL)/device/connect"

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
      Logger.log(.websocket, "Reconnecting with new user identity...")
      stopConnection()
    }
    startConnection()
  }

  func clearUserID() {
    guard userID != nil else { return }
    Logger.log(.websocket, "User ID cleared")
    userID = nil

    guard isEnabled, isConnected else { return }

    Logger.log(.websocket, "Reconnecting as anonymous...")
    stopConnection()
    startConnection()
  }

  func retry() {
    guard isEnabled else { return }
    Logger.log(.websocket, "User requested retry")
    stopConnection()
    startConnection()
  }

  // MARK: - Connection Lifecycle

  private func startConnection() {
    connectionTask?.cancel()
    connectionTask = Task { @MainActor in
      isConnectionLoopActive = true
      defer { isConnectionLoopActive = false }

      var attempt = 0
      var delay: TimeInterval = 1

      while !Task.isCancelled {
        guard isNetworkAvailable else {
          Logger.log(.websocket, "Network unavailable, waiting...")
          connectionState = .disconnected
          try? await Task.sleep(for: .seconds(1))
          continue
        }

        if attempt > 0 {
          connectionState = .reconnecting(attempt: attempt, nextRetryIn: delay)
          Logger.log(.websocket, "Reconnection attempt \(attempt) in \(String(format: "%.1f", delay))s...")
          await countdown(delay)
          guard !Task.isCancelled else { break }
        }

        attempt += 1
        let success = await attemptConnect()

        if success {
          Logger.success(.websocket, attempt > 1 ? "Reconnected after \(attempt) attempts" : "Connected")
          break
        }

        // Exponential backoff: 1, 2, 4, 8, 16, 32, 60... after 10 attempts: 300
        delay = attempt < 10 ? min(delay * 2, 60) : 300
      }
    }
  }

  private func stopConnection() {
    connectionTask?.cancel()
    connectionTask = nil
    cleanupConnection()
    connectionState = .disconnected
    Logger.log(.websocket, "Disconnected")
  }

  private func attemptConnect() async -> Bool {
    guard !Task.isCancelled else { return false }

    guard var urlComponents = URLComponents(string: serverURL) else {
      connectionState = .failed("Invalid server URL")
      Logger.error(.websocket, "Invalid server URL: \(serverURL)")
      return false
    }

    guard urlComponents.scheme == "wss" || urlComponents.scheme == "ws" else {
      let scheme = urlComponents.scheme ?? "nil"
      connectionState = .failed("Invalid protocol: \(scheme)")
      Logger.error(.websocket, "WebSocket URL must use wss:// or ws://, got: \(scheme)")
      return false
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
      return false
    }

    Logger.log(.websocket, "Connecting to: \(urlComponents.host ?? "unknown")")
    connectionState = .connecting

    cleanupConnection()

    let configuration = URLSessionConfiguration.default
    configuration.timeoutIntervalForRequest = DeviceConfig.connectionRequestTimeout
    configuration.timeoutIntervalForResource = 0
    configuration.waitsForConnectivity = true
    configuration.networkServiceType = .responsiveData
    urlSession = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)

    webSocketTask = urlSession?.webSocketTask(with: url)
    webSocketTask?.resume()
    receiveMessage()

    // Wait for connection with timeout
    let deadline = Date().addingTimeInterval(DeviceConfig.connectionTimeout)
    while !Task.isCancelled, Date() < deadline {
      if isConnected { return true }
      if case .failed = connectionState { return false }
      try? await Task.sleep(for: .milliseconds(100))
    }

    // Don't report timeout if cancelled - connection was intentionally interrupted
    guard !Task.isCancelled else { return false }

    if !isConnected {
      Logger.error(.websocket, "Connection timeout")
      connectionState = .failed("Connection timeout")
      cleanupConnection()
    }

    return false
  }

  private func countdown(_ seconds: TimeInterval) async {
    var remaining = seconds
    while remaining > 0, !Task.isCancelled {
      if case let .reconnecting(attempt, _) = connectionState {
        connectionState = .reconnecting(attempt: attempt, nextRetryIn: remaining)
      }
      try? await Task.sleep(for: .seconds(1))
      remaining -= 1
    }
  }

  private func cleanupConnection() {
    stopHeartbeat()
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
      connectionState = .connected
      lastHeartbeatResponse = Date()
      startHeartbeat()
    }
  }

  nonisolated func urlSession(
    _: URLSession,
    webSocketTask _: URLSessionWebSocketTask,
    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
    reason _: Data?
  ) {
    Task { @MainActor in
      connectionState = .disconnected
      stopHeartbeat()
      Logger.log(.websocket, "Closed: \(closeCode.rawValue)")
      if isEnabled, isNetworkAvailable {
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

      Logger.error(.websocket, "Connection error: \(error.localizedDescription)")
      connectionState = .failed(error.localizedDescription)

      // Reconnect if connection loop is not already running
      if isEnabled, isNetworkAvailable, !isConnectionLoopActive {
        startConnection()
      }
    }
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
          if self.isConnected {
            self.receiveMessage()
          }
        case let .failure(error):
          let nsError = error as NSError
          // Ignore cancelled errors - expected during cleanup
          if nsError.domain == NSURLErrorDomain, nsError.code == -999 { return }

          Logger.error(.websocket, "Receive error: \(error.localizedDescription)")
          self.connectionState = .disconnected

          // Reconnect if connection loop is not already running
          if self.isEnabled, self.isNetworkAvailable, !self.isConnectionLoopActive {
            self.startConnection()
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
          connectionState = .disconnected
          stopHeartbeat()
          if isEnabled, isNetworkAvailable {
            startConnection()
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
          Logger.log(.websocket, "Network recovered")
          if isEnabled, !isConnected {
            startConnection()
          }
        } else if wasAvailable, !isNetworkAvailable {
          Logger.log(.websocket, "Network lost")
        }
      }
    }
    networkMonitor.start(queue: .global(qos: .utility))
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
