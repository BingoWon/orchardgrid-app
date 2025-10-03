/**
 * WebSocketClient.swift
 * OrchardGrid Device Client
 *
 * Connects to Cloudflare platform and processes LLM tasks
 */

import Foundation
@preconcurrency import FoundationModels

// MARK: - Message Types

struct TaskMessage: Codable, Sendable {
  let id: String
  let type: String // "task"
  let payload: ChatRequest
}

struct ResponseMessage: Codable, Sendable {
  let id: String
  let type: String // "response"
  let payload: ChatResponse
}

struct StreamChunkMessage: Codable, Sendable {
  let id: String
  let type: String // "stream"
  let delta: String
}

struct StreamEndMessage: Codable, Sendable {
  let id: String
  let type: String // "stream_end"
}

struct ErrorMessage: Codable, Sendable {
  let id: String
  let type: String // "error"
  let error: String
}

struct HeartbeatMessage: Codable, Sendable {
  let type: String // "heartbeat"
}

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

  // State
  private(set) var isConnected = false
  private(set) var lastError: String?
  private(set) var tasksProcessed = 0
  var isEnabled = false {
    didSet {
      guard oldValue != isEnabled else { return }
      UserDefaults.standard.set(isEnabled, forKey: "WebSocketClient.isEnabled")
      if isEnabled {
        if userID != nil {
          connect()
        }
      } else {
        disconnect()
        lastError = nil // Clear error when user disables
      }
    }
  }

  // WebSocket
  private var webSocketTask: URLSessionWebSocketTask?
  private var urlSession: URLSession?
  private var shouldAutoReconnect = false
  private var reconnectTask: Task<Void, Never>?
  private var heartbeatTask: Task<Void, Never>?

  // LLM Processing
  private let model = SystemLanguageModel.default
  private let jsonEncoder = JSONEncoder()
  private let jsonDecoder = JSONDecoder()

  // Constants
  private let heartbeatInterval: TimeInterval = 30 // 30 seconds

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
      platform = "macos"
    #elseif os(iOS)
      platform = "ios"
    #else
      platform = "unknown"
    #endif

    osVersion = ProcessInfo.processInfo.operatingSystemVersionString

    // Restore previous state
    isEnabled = UserDefaults.standard.bool(forKey: "WebSocketClient.isEnabled")

    super.init()

    jsonEncoder.keyEncodingStrategy = .convertToSnakeCase
    jsonDecoder.keyDecodingStrategy = .convertFromSnakeCase
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
    lastError = nil
    connect()
  }

  // MARK: - URLSessionWebSocketDelegate

  nonisolated func urlSession(
    _: URLSession,
    webSocketTask _: URLSessionWebSocketTask,
    didOpenWithProtocol _: String?
  ) {
    Task { @MainActor in
      isConnected = true
      lastError = nil
      reconnectTask?.cancel()
      reconnectTask = nil
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
      isConnected = false
      stopHeartbeat()
      Logger.log(.websocket, "Closed: \(closeCode.rawValue)")

      if shouldAutoReconnect {
        lastError = "Connection closed unexpectedly"
        startReconnection()
      }
    }
  }

  // MARK: - Connection Management

  func connect() {
    guard !isConnected else {
      Logger.log(.websocket, "Already connected, skipping")
      return
    }
    guard let userID else {
      lastError = "User ID not set"
      Logger.error(.websocket, "Cannot connect: User ID not set")
      return
    }

    Logger.log(.websocket, "Starting connection...")
    shouldAutoReconnect = true
    reconnectTask?.cancel()
    reconnectTask = nil
    lastError = nil

    // Create URL with device ID, user ID, platform, and OS version
    guard var urlComponents = URLComponents(string: serverURL) else {
      lastError = "Invalid server URL"
      return
    }
    urlComponents.queryItems = [
      URLQueryItem(name: "device_id", value: deviceID),
      URLQueryItem(name: "user_id", value: userID),
      URLQueryItem(name: "platform", value: platform),
      URLQueryItem(name: "os_version", value: osVersion),
    ]

    guard let url = urlComponents.url else {
      lastError = "Failed to construct URL"
      return
    }

    // Create URLSession with delegate
    let configuration = URLSessionConfiguration.default
    configuration.timeoutIntervalForRequest = 30
    configuration.timeoutIntervalForResource = 300
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
    reconnectTask?.cancel()
    reconnectTask = nil
    stopHeartbeat()

    webSocketTask?.cancel(with: .goingAway, reason: nil)
    webSocketTask = nil
    urlSession?.invalidateAndCancel()
    urlSession = nil
    isConnected = false
    lastError = nil

    Logger.log(.websocket, "Disconnected")
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
      let taskMessage = try jsonDecoder.decode(TaskMessage.self, from: data)

      guard taskMessage.type == "task" else {
        Logger.log(.websocket, "Unknown message type: \(taskMessage.type)")
        return
      }

      Logger.log(.websocket, "Received task: \(taskMessage.id)")

      // Process task
      await processTask(taskMessage)

    } catch {
      Logger.error(.websocket, "Failed to decode message: \(error)")
      lastError = "Message decode error: \(error.localizedDescription)"
    }
  }

  private func handleError(_ error: Error) {
    Logger.error(.websocket, "\(error)")
    lastError = error.localizedDescription
    isConnected = false
    // Don't modify isEnabled - let user control it
  }

  // MARK: - Heartbeat

  private func startHeartbeat() {
    stopHeartbeat()

    heartbeatTask = Task { @MainActor in
      while !Task.isCancelled, isConnected {
        try? await Task.sleep(for: .seconds(heartbeatInterval))

        guard isConnected else { return }

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

  // MARK: - Reconnection

  private func startReconnection() {
    reconnectTask?.cancel()

    reconnectTask = Task { @MainActor in
      var delay = 1.0
      var attempts = 0
      let maxAttempts = 10

      while attempts < maxAttempts, !isConnected, shouldAutoReconnect {
        attempts += 1
        Logger.log(
          .websocket,
          "Reconnection attempt \(attempts)/\(maxAttempts) in \(String(format: "%.1f", delay))s..."
        )

        try? await Task.sleep(for: .seconds(delay))

        guard shouldAutoReconnect, !isConnected else {
          Logger.log(.websocket, "Reconnection cancelled")
          return
        }

        // Reconnect
        disconnect()
        try? await Task.sleep(for: .seconds(0.5))
        connect()

        // Wait to check if connection succeeded
        try? await Task.sleep(for: .seconds(2))

        if isConnected {
          Logger.success(.websocket, "Reconnected")
          return
        }

        // Exponential backoff with max 60 seconds
        delay = min(delay * 2, 60)
      }

      if !isConnected, shouldAutoReconnect {
        Logger.error(.websocket, "Max reconnection attempts reached")
        lastError = "Failed to reconnect after \(maxAttempts) attempts"
      }
    }
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

    guard case .available = model.availability else {
      throw NSError(domain: "WebSocketClient", code: 1, userInfo: [
        NSLocalizedDescriptionKey: "Apple Intelligence not available",
      ])
    }

    guard let lastMessage = request.messages.last, lastMessage.role == "user" else {
      throw NSError(domain: "WebSocketClient", code: 2, userInfo: [
        NSLocalizedDescriptionKey: "Last message must be from user",
      ])
    }

    // Build transcript
    let transcript = buildTranscript(from: request.messages)
    let session = LanguageModelSession(transcript: transcript)

    // Stream response
    var previousContent = ""

    if let responseFormat = request.response_format,
       responseFormat.type == "json_schema",
       let jsonSchema = responseFormat.json_schema
    {
      // Structured output streaming
      let converter = SchemaConverter()
      let appleSchema = try converter.convert(jsonSchema)
      let stream = session.streamResponse(to: lastMessage.content, schema: appleSchema)

      for try await snapshot in stream {
        let fullContent = snapshot.content.jsonString
        let delta = String(fullContent.dropFirst(previousContent.count))

        if !delta.isEmpty {
          let chunkMessage = StreamChunkMessage(
            id: taskId,
            type: "stream",
            delta: delta
          )
          await sendMessage(chunkMessage)
        }

        previousContent = fullContent
      }
    } else {
      // Regular text streaming
      let stream = session.streamResponse(to: lastMessage.content)

      for try await snapshot in stream {
        let fullContent = snapshot.content
        let delta = String(fullContent.dropFirst(previousContent.count))

        if !delta.isEmpty {
          let chunkMessage = StreamChunkMessage(
            id: taskId,
            type: "stream",
            delta: delta
          )
          await sendMessage(chunkMessage)
        }

        previousContent = fullContent
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
    guard case .available = model.availability else {
      throw NSError(domain: "WebSocketClient", code: 1, userInfo: [
        NSLocalizedDescriptionKey: "Apple Intelligence not available",
      ])
    }

    guard let lastMessage = request.messages.last, lastMessage.role == "user" else {
      throw NSError(domain: "WebSocketClient", code: 2, userInfo: [
        NSLocalizedDescriptionKey: "Last message must be from user",
      ])
    }

    // Build transcript
    let transcript = buildTranscript(from: request.messages)
    let session = LanguageModelSession(transcript: transcript)

    // Generate response
    let content: String

    if let responseFormat = request.response_format,
       responseFormat.type == "json_schema",
       let jsonSchema = responseFormat.json_schema
    {
      // Structured output
      let converter = SchemaConverter()
      let appleSchema = try converter.convert(jsonSchema)
      let result = try await session.respond(to: lastMessage.content, schema: appleSchema)
      content = result.content.jsonString
    } else {
      // Regular text output
      let result = try await session.respond(to: lastMessage.content)
      content = result.content
    }

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

  private func buildTranscript(from messages: [ChatMessage]) -> Transcript {
    var entries: [Transcript.Entry] = []

    for message in messages {
      switch message.role {
      case "system":
        // System messages are handled separately in LanguageModelSession
        break

      case "user":
        let prompt = Transcript.Prompt(
          segments: [.text(.init(content: message.content))]
        )
        entries.append(.prompt(prompt))

      case "assistant":
        let response = Transcript.Response(
          assetIDs: [],
          segments: [.text(.init(content: message.content))]
        )
        entries.append(.response(response))

      default:
        break
      }
    }

    return Transcript(entries: entries)
  }

  private func estimateTokens(_ messages: [ChatMessage]) -> Int {
    // Rough estimation: ~4 characters per token
    let totalChars = messages.reduce(0) { $0 + $1.content.count }
    return max(1, totalChars / 4)
  }

  // MARK: - Message Sending

  private func sendMessage(_ message: some Encodable) async {
    do {
      let data = try jsonEncoder.encode(message)
      guard let text = String(data: data, encoding: .utf8) else {
        Logger.error(.websocket, "Failed to encode message as string")
        return
      }

      let wsMessage = URLSessionWebSocketTask.Message.string(text)
      try await webSocketTask?.send(wsMessage)

    } catch {
      Logger.error(.websocket, "Failed to send message: \(error)")
      lastError = "Send error: \(error.localizedDescription)"
    }
  }
}
