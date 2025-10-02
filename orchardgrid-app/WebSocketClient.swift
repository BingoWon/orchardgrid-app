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

// MARK: - WebSocket Client

@Observable
@MainActor
final class WebSocketClient {
  // Configuration
  private let serverURL: String
  private let deviceID: String
  private let userID: String
  private let platform: String
  private let osVersion: String

  // State
  private(set) var isConnected = false
  private(set) var lastError: String?
  private(set) var tasksProcessed = 0

  // WebSocket
  private var webSocketTask: URLSessionWebSocketTask?
  private var urlSession: URLSession?

  // LLM Processing
  private let model = SystemLanguageModel.default
  private let jsonEncoder = JSONEncoder()
  private let jsonDecoder = JSONDecoder()

  init(
    serverURL: String? = nil,
    deviceID: String? = nil,
    userID: String? = nil
  ) {
    // Configuration from environment or defaults
    self.serverURL = serverURL
      ?? ProcessInfo.processInfo.environment["ORCHARDGRID_SERVER_URL"]
      ?? "wss://orchardgrid-api.bingow.workers.dev/device/connect"

    self.deviceID = deviceID
      ?? ProcessInfo.processInfo.environment["ORCHARDGRID_DEVICE_ID"]
      ?? UUID().uuidString

    self.userID = userID
      ?? ProcessInfo.processInfo.environment["ORCHARDGRID_USER_ID"]
      ?? "anonymous"

    #if os(macOS)
      platform = "macos"
    #elseif os(iOS)
      platform = "ios"
    #else
      platform = "unknown"
    #endif

    osVersion = ProcessInfo.processInfo.operatingSystemVersionString

    jsonEncoder.keyEncodingStrategy = .convertToSnakeCase
    jsonDecoder.keyDecodingStrategy = .convertFromSnakeCase
  }

  // MARK: - Connection Management

  func connect() {
    guard !isConnected else { return }

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

    // Create URLSession
    let configuration = URLSessionConfiguration.default
    configuration.timeoutIntervalForRequest = 30
    configuration.timeoutIntervalForResource = 300
    urlSession = URLSession(configuration: configuration)

    // Create WebSocket task
    webSocketTask = urlSession?.webSocketTask(with: url)
    webSocketTask?.resume()

    isConnected = true
    lastError = nil

    print("🔌 Connecting to platform: \(url.absoluteString)")
    print("📱 Device: \(deviceID), Platform: \(platform), OS: \(osVersion)")

    // Start receiving messages
    receiveMessage()
  }

  func disconnect() {
    webSocketTask?.cancel(with: .goingAway, reason: nil)
    webSocketTask = nil
    urlSession?.invalidateAndCancel()
    urlSession = nil
    isConnected = false

    print("🔌 Disconnected from platform")
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
        print("⚠️ Unknown message type: \(taskMessage.type)")
        return
      }

      print("\n" + String(repeating: "=", count: 80))
      print("📥 Received Task: \(taskMessage.id)")
      print(String(repeating: "=", count: 80))

      // Process task
      await processTask(taskMessage)

    } catch {
      print("❌ Failed to decode message: \(error)")
      lastError = "Message decode error: \(error.localizedDescription)"
    }
  }

  private func handleError(_ error: Error) {
    print("❌ WebSocket error: \(error)")
    lastError = error.localizedDescription
    isConnected = false

    // Exponential backoff reconnection
    Task { @MainActor in
      var delay = 1.0
      var attempts = 0
      let maxAttempts = 10

      while attempts < maxAttempts, !isConnected {
        attempts += 1
        print(
          "🔄 Reconnection attempt \(attempts)/\(maxAttempts) in \(String(format: "%.1f", delay))s..."
        )

        try? await Task.sleep(for: .seconds(delay))

        if !isConnected {
          connect()

          // Wait a bit to check if connection succeeded
          try? await Task.sleep(for: .seconds(1))

          if isConnected {
            print("✅ Reconnected successfully")
            return
          }

          // Exponential backoff with max 60 seconds
          delay = min(delay * 2, 60)
        }
      }

      if !isConnected {
        print("❌ Max reconnection attempts reached")
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
      print("✅ Task completed in \(String(format: "%.2f", duration))s")
      print(String(repeating: "=", count: 80) + "\n")

    } catch {
      print("❌ Task failed: \(error)")

      let errorMessage = ErrorMessage(
        id: taskMessage.id,
        type: "error",
        error: error.localizedDescription
      )

      await sendMessage(errorMessage)
    }
  }

  private func generateStreamingResponse(for request: ChatRequest, taskId: String) async throws {
    print("🌊 [Streaming] Starting streaming response for task: \(taskId)")

    guard case .available = model.availability else {
      print("❌ [Streaming] Apple Intelligence not available")
      throw NSError(domain: "WebSocketClient", code: 1, userInfo: [
        NSLocalizedDescriptionKey: "Apple Intelligence not available",
      ])
    }

    guard let lastMessage = request.messages.last, lastMessage.role == "user" else {
      print("❌ [Streaming] Last message must be from user")
      throw NSError(domain: "WebSocketClient", code: 2, userInfo: [
        NSLocalizedDescriptionKey: "Last message must be from user",
      ])
    }

    print("🌊 [Streaming] Building transcript...")
    // Build transcript
    let transcript = buildTranscript(from: request.messages)
    let session = LanguageModelSession(transcript: transcript)

    print("🌊 [Streaming] Starting stream...")
    // Stream response
    var previousContent = ""

    if let responseFormat = request.response_format,
       responseFormat.type == "json_schema",
       let jsonSchema = responseFormat.json_schema
    {
      // Structured output streaming
      print("🌊 [Streaming] Using structured output")
      let converter = SchemaConverter()
      let appleSchema = try converter.convert(jsonSchema)
      let stream = session.streamResponse(to: lastMessage.content, schema: appleSchema)

      var chunkCount = 0
      for try await snapshot in stream {
        chunkCount += 1
        let fullContent = snapshot.content.jsonString
        let delta = String(fullContent.dropFirst(previousContent.count))

        print("🌊 [Streaming] Chunk \(chunkCount): delta length = \(delta.count)")

        if !delta.isEmpty {
          let chunkMessage = StreamChunkMessage(
            id: taskId,
            type: "stream",
            delta: delta
          )
          await sendMessage(chunkMessage)
          print("🌊 [Streaming] Sent chunk \(chunkCount)")
        }

        previousContent = fullContent
      }
      print("🌊 [Streaming] Structured stream completed with \(chunkCount) chunks")
    } else {
      // Regular text streaming
      print("🌊 [Streaming] Using regular text output")
      let stream = session.streamResponse(to: lastMessage.content)

      var chunkCount = 0
      for try await snapshot in stream {
        chunkCount += 1
        let fullContent = snapshot.content
        let delta = String(fullContent.dropFirst(previousContent.count))

        print(
          "🌊 [Streaming] Chunk \(chunkCount): delta length = \(delta.count), full length = \(fullContent.count)"
        )

        if !delta.isEmpty {
          let chunkMessage = StreamChunkMessage(
            id: taskId,
            type: "stream",
            delta: delta
          )
          await sendMessage(chunkMessage)
          print("🌊 [Streaming] Sent chunk \(chunkCount)")
        }

        previousContent = fullContent
      }
      print("🌊 [Streaming] Text stream completed with \(chunkCount) chunks")
    }

    // Send stream end
    print("🌊 [Streaming] Sending stream end message")
    let endMessage = StreamEndMessage(
      id: taskId,
      type: "stream_end"
    )
    await sendMessage(endMessage)
    print("🌊 [Streaming] Stream end message sent")
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
        print("❌ Failed to encode message as string")
        return
      }

      let wsMessage = URLSessionWebSocketTask.Message.string(text)
      try await webSocketTask?.send(wsMessage)

    } catch {
      print("❌ Failed to send message: \(error)")
      lastError = "Send error: \(error.localizedDescription)"
    }
  }
}
