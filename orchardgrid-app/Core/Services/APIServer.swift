/**
 * APIServer.swift
 * OrchardGrid Local API Server
 *
 * Provides Standard Chat Completion API for local apps
 * Note: Lifecycle managed by SharingManager
 */

import Foundation
@preconcurrency import FoundationModels
import Network
import OSLog

// MARK: - HTTP Request

struct HTTPRequest: Sendable {
  let method: String
  let path: String
  let headers: [String: String]
  let body: Data?

  nonisolated init?(rawRequest: String) {
    let lines = rawRequest.components(separatedBy: "\r\n")
    guard let firstLine = lines.first else { return nil }

    let components = firstLine.components(separatedBy: " ")
    guard components.count >= 2 else { return nil }

    method = components[0]
    path = components[1]

    var headers: [String: String] = [:]
    var bodyStart = 0

    for (index, line) in lines.enumerated() where index > 0 {
      if line.isEmpty {
        bodyStart = index + 1
        break
      }
      if let colonIndex = line.firstIndex(of: ":") {
        let key = String(line[..<colonIndex]).trimmingCharacters(in: .whitespaces)
        let value = String(line[line.index(after: colonIndex)...])
          .trimmingCharacters(in: .whitespaces)
        headers[key] = value
      }
    }

    self.headers = headers

    if bodyStart < lines.count {
      let bodyString = lines[bodyStart...].joined(separator: "\r\n")
      body = bodyString.data(using: .utf8)
    } else {
      body = nil
    }
  }
}

// MARK: - API Server

@Observable
@MainActor
final class APIServer {
  // MARK: - Configuration

  private let config = AppConfiguration.default.apiServer

  // MARK: - State

  private(set) var isRunning = false
  private(set) var requestCount = 0
  private(set) var lastRequest = ""
  private(set) var lastResponse = ""
  private(set) var errorMessage = ""
  private(set) var localIPAddress: String?

  nonisolated var port: UInt16 { config.port }

  // MARK: - Enabled State (Managed by SharingManager)

  var isEnabled = false {
    didSet {
      guard oldValue != isEnabled else { return }
      if isEnabled {
        Task { await start() }
      } else {
        stop()
      }
    }
  }

  // MARK: - Private State

  private var listener: NWListener?
  private var pathMonitor: NWPathMonitor?
  private let jsonDecoder = JSONDecoder()

  // MARK: - Injected Dependencies

  private let llmProcessor: LLMProcessor

  // MARK: - Initialization

  init(llmProcessor: LLMProcessor) {
    self.llmProcessor = llmProcessor
    startNetworkMonitoring()
  }

  // MARK: - Server Lifecycle

  nonisolated func start() async {
    await MainActor.run {
      guard !isRunning else { return }
    }

    do {
      let parameters = NWParameters.tcp
      parameters.allowLocalEndpointReuse = true
      let listener = try NWListener(using: parameters, on: NWEndpoint.Port(integerLiteral: port))

      listener.stateUpdateHandler = { [weak self] state in
        Task { @MainActor [weak self] in
          guard let self else { return }
          switch state {
          case .ready:
            isRunning = true
            errorMessage = ""
          case let .failed(error):
            isRunning = false
            errorMessage = "Failed: \(error.localizedDescription)"
          case .cancelled:
            isRunning = false
          default:
            break
          }
        }
      }

      listener.newConnectionHandler = { [weak self] connection in
        Task { @MainActor in
          await self?.handleConnection(connection)
        }
      }

      await MainActor.run {
        self.listener = listener
      }

      listener.start(queue: .global())
    } catch {
      await MainActor.run {
        self.errorMessage = "Failed: \(error.localizedDescription)"
      }
    }
  }

  func stop() {
    listener?.cancel()
    listener = nil
    isRunning = false
    errorMessage = ""
  }

  // MARK: - Network Monitoring

  private func startNetworkMonitoring() {
    let monitor = NWPathMonitor()
    pathMonitor = monitor

    monitor.pathUpdateHandler = { [weak self] _ in
      Task { @MainActor [weak self] in
        self?.updateLocalIPAddress()
      }
    }

    monitor.start(queue: .global())
    updateLocalIPAddress()
  }

  private func updateLocalIPAddress() {
    localIPAddress = NetworkInfo.localIPAddress
  }

  // MARK: - Request Handling

  private nonisolated func handleConnection(_ connection: NWConnection) async {
    connection.start(queue: .global())

    guard let rawRequest = await receiveRequest(from: connection),
          let httpRequest = HTTPRequest(rawRequest: rawRequest)
    else {
      await sendError(.badRequest, to: connection)
      return
    }

    await processRequest(httpRequest, connection: connection)
  }

  private nonisolated func receiveRequest(from connection: NWConnection) async -> String? {
    await withCheckedContinuation { continuation in
      connection.receive(
        minimumIncompleteLength: 1,
        maximumLength: config.maxRequestSize
      ) { data, _, _, _ in
        if let data, let request = String(data: data, encoding: .utf8) {
          continuation.resume(returning: request)
        } else {
          continuation.resume(returning: nil)
        }
      }
    }
  }

  private nonisolated func processRequest(_ request: HTTPRequest, connection: NWConnection) async {
    switch (request.method, request.path) {
    case ("GET", "/v1/models"):
      await sendModels(to: connection)
    case ("POST", "/v1/chat/completions"):
      await handleChatCompletion(request: request, connection: connection)
    default:
      await sendError(.notFound, to: connection)
    }
  }

  private nonisolated func handleChatCompletion(
    request: HTTPRequest,
    connection: NWConnection
  ) async {
    guard let body = request.body else {
      await sendError(.badRequest, message: "Missing request body", to: connection)
      return
    }

    do {
      let chatRequest = try await MainActor.run {
        try jsonDecoder.decode(ChatRequest.self, from: body)
      }

      guard !chatRequest.messages.isEmpty else {
        await sendError(.badRequest, message: "Messages array cannot be empty", to: connection)
        return
      }

      let systemPrompt = chatRequest.messages.first(where: { $0.role == "system" })?
        .content ?? LLMConfig.defaultSystemPrompt
      let conversationMessages = chatRequest.messages.filter { $0.role != "system" }

      guard let lastUserMessage = conversationMessages.last(where: { $0.role == "user" }) else {
        await sendError(.badRequest, message: "No user message found", to: connection)
        return
      }

      await MainActor.run {
        self.requestCount += 1
        self.lastRequest = lastUserMessage.content
      }

      if chatRequest.stream == true {
        await streamResponse(
          messages: conversationMessages,
          systemPrompt: systemPrompt,
          responseFormat: chatRequest.response_format,
          connection: connection
        )
      } else {
        await sendResponse(
          messages: conversationMessages,
          systemPrompt: systemPrompt,
          responseFormat: chatRequest.response_format,
          connection: connection
        )
      }
    } catch {
      await sendError(
        .badRequest,
        message: "Invalid request format: \(error.localizedDescription)",
        to: connection
      )
    }
  }

  private nonisolated func sendResponse(
    messages: [ChatMessage],
    systemPrompt: String,
    responseFormat: ResponseFormat?,
    connection: NWConnection
  ) async {
    do {
      let content = try await llmProcessor.processRequest(
        messages: messages,
        systemPrompt: systemPrompt,
        responseFormat: responseFormat
      )

      await MainActor.run {
        self.lastResponse = content
      }

      let chatResponse = ChatResponse(
        id: "chatcmpl-\(UUID().uuidString.prefix(8))",
        object: "chat.completion",
        created: Int(Date().timeIntervalSince1970),
        model: "apple-intelligence",
        choices: [
          .init(
            index: 0,
            message: .init(role: "assistant", content: content),
            finishReason: "stop"
          ),
        ],
        usage: .init(promptTokens: 0, completionTokens: 0, totalTokens: 0)
      )

      await send(chatResponse, to: connection)
    } catch let error as LLMError {
      switch error {
      case .modelUnavailable:
        await sendError(.serviceUnavailable, message: "Model not available", to: connection)
      case let .invalidRequest(message):
        await sendError(.badRequest, message: message, to: connection)
      case let .processingFailed(message):
        await sendError(.internalError, message: message, to: connection)
      }
    } catch {
      let errorMessage = error.localizedDescription
      if errorMessage.contains("context") || errorMessage.contains("window") {
        await sendError(
          .badRequest,
          message: "Context window exceeded. Please start a new conversation.",
          to: connection
        )
      } else {
        await sendError(.internalError, message: "\(errorMessage)", to: connection)
      }
    }
  }

  private nonisolated func streamResponse(
    messages: [ChatMessage],
    systemPrompt: String,
    responseFormat: ResponseFormat?,
    connection: NWConnection
  ) async {
    let id = "chatcmpl-\(UUID().uuidString.prefix(8))"
    let timestamp = Int(Date().timeIntervalSince1970)

    await sendStreamHeaders(to: connection)

    let initialChunk = StreamChunk(
      id: id,
      object: "chat.completion.chunk",
      created: timestamp,
      model: "apple-intelligence",
      choices: [.init(index: 0, delta: .init(role: "assistant", content: ""), finishReason: nil)]
    )
    await sendStreamChunk(initialChunk, to: connection)

    do {
      let fullContent = try await llmProcessor.processRequest(
        messages: messages,
        systemPrompt: systemPrompt,
        responseFormat: responseFormat
      ) { [weak self] delta in
        Task {
          let chunk = StreamChunk(
            id: id,
            object: "chat.completion.chunk",
            created: timestamp,
            model: "apple-intelligence",
            choices: [.init(
              index: 0,
              delta: .init(role: "assistant", content: delta),
              finishReason: nil
            )]
          )
          await self?.sendStreamChunk(chunk, to: connection)
        }
      }

      await MainActor.run {
        self.lastResponse = fullContent
      }

      let finalChunk = StreamChunk(
        id: id,
        object: "chat.completion.chunk",
        created: timestamp,
        model: "apple-intelligence",
        choices: [.init(
          index: 0,
          delta: .init(role: "assistant", content: ""),
          finishReason: "stop"
        )]
      )
      await sendStreamChunk(finalChunk, to: connection)
      await sendStreamEnd(to: connection)
    } catch let error as LLMError {
      let errorContent = switch error {
      case .modelUnavailable:
        "Error: Model not available"
      case let .invalidRequest(message):
        "Error: \(message)"
      case let .processingFailed(message):
        if message.contains("context") || message.contains("window") {
          "Error: Context window exceeded. Please start a new conversation."
        } else {
          "Error: \(message)"
        }
      }

      let errorChunk = StreamChunk(
        id: id,
        object: "chat.completion.chunk",
        created: timestamp,
        model: "apple-intelligence",
        choices: [.init(
          index: 0,
          delta: .init(role: "assistant", content: errorContent),
          finishReason: "error"
        )]
      )
      await sendStreamChunk(errorChunk, to: connection)
      await sendStreamEnd(to: connection)
    } catch {
      let errorContent = "Error: \(error.localizedDescription)"
      let chunk = StreamChunk(
        id: id,
        object: "chat.completion.chunk",
        created: timestamp,
        model: "apple-intelligence",
        choices: [.init(
          index: 0,
          delta: .init(role: "assistant", content: errorContent),
          finishReason: "error"
        )]
      )
      await sendStreamChunk(chunk, to: connection)
      await sendStreamEnd(to: connection)
    }

    connection.cancel()
  }

  // MARK: - Response Helpers

  private nonisolated func sendModels(to connection: NWConnection) async {
    let response = ModelsResponse(
      object: "list",
      data: [
        .init(
          id: "apple-intelligence",
          object: "model",
          created: Int(Date().timeIntervalSince1970),
          ownedBy: "apple"
        ),
      ]
    )
    await send(response, to: connection)
  }

  private nonisolated func send(_ response: some Encodable, to connection: NWConnection) async {
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase

    guard let data = try? encoder.encode(response),
          let json = String(data: data, encoding: .utf8)
    else { return }

    let httpResponse = """
    HTTP/1.1 200 OK\r
    Content-Type: application/json\r
    Content-Length: \(data.count)\r
    Connection: close\r
    \r
    \(json)
    """

    await send(httpResponse, to: connection, closeAfter: true)
  }

  private nonisolated func sendStreamHeaders(to connection: NWConnection) async {
    let headers = """
    HTTP/1.1 200 OK\r
    Content-Type: text/event-stream\r
    Cache-Control: no-cache\r
    Connection: keep-alive\r
    \r

    """
    await send(headers, to: connection, closeAfter: false)
  }

  private nonisolated func sendStreamChunk(
    _ chunk: some Encodable,
    to connection: NWConnection
  ) async {
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase

    guard let data = try? encoder.encode(chunk),
          let json = String(data: data, encoding: .utf8)
    else { return }

    await send("data: \(json)\n\n", to: connection, closeAfter: false)
  }

  private nonisolated func sendStreamEnd(to connection: NWConnection) async {
    await send("data: [DONE]\n\n", to: connection, closeAfter: false)
  }

  private nonisolated func sendError(
    _ error: HTTPError,
    message: String? = nil,
    to connection: NWConnection
  ) async {
    let errorResponse = ErrorResponse(
      error: .init(
        message: message ?? error.message,
        type: error.type,
        code: error.code
      )
    )

    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase

    guard let data = try? encoder.encode(errorResponse),
          let json = String(data: data, encoding: .utf8)
    else {
      let fallback = """
      HTTP/1.1 \(error.statusCode) \(error.statusMessage)\r
      Connection: close\r
      \r

      """
      await send(fallback, to: connection, closeAfter: true)
      return
    }

    let httpResponse = """
    HTTP/1.1 \(error.statusCode) \(error.statusMessage)\r
    Content-Type: application/json\r
    Content-Length: \(data.count)\r
    Connection: close\r
    \r
    \(json)
    """

    await send(httpResponse, to: connection, closeAfter: true)
  }

  private nonisolated func send(
    _ text: String,
    to connection: NWConnection,
    closeAfter: Bool
  ) async {
    guard let data = text.data(using: .utf8) else { return }

    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      connection.send(content: data, completion: .contentProcessed { _ in
        if closeAfter {
          connection.cancel()
        }
        continuation.resume()
      })
    }
  }
}

// MARK: - HTTP Error

enum HTTPError: Sendable {
  case badRequest
  case notFound
  case internalError
  case serviceUnavailable

  nonisolated var statusCode: Int {
    switch self {
    case .badRequest: 400
    case .notFound: 404
    case .internalError: 500
    case .serviceUnavailable: 503
    }
  }

  nonisolated var statusMessage: String {
    switch self {
    case .badRequest: "Bad Request"
    case .notFound: "Not Found"
    case .internalError: "Internal Server Error"
    case .serviceUnavailable: "Service Unavailable"
    }
  }

  nonisolated var message: String {
    switch self {
    case .badRequest: "The request was malformed or invalid"
    case .notFound: "The requested resource was not found"
    case .internalError: "An internal server error occurred"
    case .serviceUnavailable: "The service is temporarily unavailable"
    }
  }

  nonisolated var type: String {
    switch self {
    case .badRequest: "invalid_request_error"
    case .notFound: "not_found_error"
    case .internalError: "internal_error"
    case .serviceUnavailable: "service_unavailable_error"
    }
  }

  nonisolated var code: String? {
    switch self {
    case .badRequest: "bad_request"
    case .notFound: "not_found"
    case .internalError: "internal_error"
    case .serviceUnavailable: "service_unavailable"
    }
  }
}
