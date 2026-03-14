import Foundation
@preconcurrency import FoundationModels
import Network

// MARK: - HTTP Request

struct HTTPRequest: Sendable {
  let method: String
  let path: String
  let headers: [String: String]
  let body: Data?

  init?(rawRequest: String) {
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

// MARK: - HTTP Response Builder

private enum HTTP {
  static func json(
    status: Int = 200,
    statusText: String = "OK",
    body: Data
  ) -> String {
    let json = String(data: body, encoding: .utf8) ?? ""
    return """
    HTTP/1.1 \(status) \(statusText)\r
    Content-Type: application/json\r
    Content-Length: \(body.count)\r
    Connection: close\r
    \r
    \(json)
    """
  }

  static let sseHeaders = """
  HTTP/1.1 200 OK\r
  Content-Type: text/event-stream\r
  Cache-Control: no-cache\r
  Connection: keep-alive\r
  \r

  """

  static func empty(status: Int, statusText: String) -> String {
    """
    HTTP/1.1 \(status) \(statusText)\r
    Connection: close\r
    \r

    """
  }
}

// MARK: - API Server

@Observable
@MainActor
final class APIServer {
  // MARK: - State

  private(set) var isRunning = false
  private(set) var requestCount = 0
  private(set) var lastRequest = ""
  private(set) var lastResponse = ""
  private(set) var errorMessage = ""
  private(set) var localIPAddress: String?

  var port: UInt16 { Config.apiServerPort }

  // MARK: - Enabled State (Managed by SharingManager)

  var isEnabled = false {
    didSet {
      guard oldValue != isEnabled else { return }
      if isEnabled { Task { await start() } } else { stop() }
    }
  }

  // MARK: - Private State

  private var listener: NWListener?
  private var pathMonitor: NWPathMonitor?

  // MARK: - Dependencies

  private let llmProcessor: LLMProcessor

  // MARK: - Initialization

  init(llmProcessor: LLMProcessor) {
    self.llmProcessor = llmProcessor
    startNetworkMonitoring()
  }

  // MARK: - Server Lifecycle

  func start() async {
    guard !isRunning else { return }

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

      self.listener = listener
      listener.start(queue: .global())
    } catch {
      errorMessage = "Failed: \(error.localizedDescription)"
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
        self?.localIPAddress = NetworkInfo.localIPAddress
      }
    }

    monitor.start(queue: .global())
    localIPAddress = NetworkInfo.localIPAddress
  }

  // MARK: - Request Handling

  private func handleConnection(_ connection: NWConnection) async {
    connection.start(queue: .global())

    guard let rawRequest = await receiveRequest(from: connection),
          let httpRequest = HTTPRequest(rawRequest: rawRequest)
    else {
      await sendError(.badRequest, to: connection)
      return
    }

    await processRequest(httpRequest, connection: connection)
  }

  private func receiveRequest(from connection: NWConnection) async -> String? {
    await withCheckedContinuation { continuation in
      connection.receive(
        minimumIncompleteLength: 1,
        maximumLength: Config.maxRequestSize
      ) { data, _, _, _ in
        if let data, let request = String(data: data, encoding: .utf8) {
          continuation.resume(returning: request)
        } else {
          continuation.resume(returning: nil)
        }
      }
    }
  }

  private func processRequest(_ request: HTTPRequest, connection: NWConnection) async {
    switch (request.method, request.path) {
    case ("GET", "/v1/models"):
      await sendModels(to: connection)
    case ("POST", "/v1/chat/completions"):
      await handleChatCompletion(request: request, connection: connection)
    case ("POST", "/v1/images/generations"):
      await handleImageGeneration(request: request, connection: connection)
    default:
      await sendError(.notFound, to: connection)
    }
  }

  // MARK: - Chat Completion

  private func handleChatCompletion(
    request: HTTPRequest,
    connection: NWConnection
  ) async {
    guard let body = request.body else {
      await sendError(.badRequest, message: "Missing request body", to: connection)
      return
    }

    do {
      let chatRequest = try JSONDecoder().decode(ChatRequest.self, from: body)

      guard !chatRequest.messages.isEmpty else {
        await sendError(.badRequest, message: "Messages array cannot be empty", to: connection)
        return
      }

      let systemPrompt = chatRequest.messages.first { $0.role == "system" }?
        .content ?? Config.defaultSystemPrompt
      let messages = chatRequest.messages.filter { $0.role != "system" }

      guard let lastUserMessage = messages.last(where: { $0.role == "user" }) else {
        await sendError(.badRequest, message: "No user message found", to: connection)
        return
      }

      requestCount += 1
      lastRequest = lastUserMessage.content

      if chatRequest.stream == true {
        await streamResponse(
          messages: messages,
          systemPrompt: systemPrompt,
          responseFormat: chatRequest.response_format,
          connection: connection
        )
      } else {
        await sendChatResponse(
          messages: messages,
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

  private func sendChatResponse(
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

      lastResponse = content
      await sendJSON(ChatResponse.create(content: content), to: connection)
    } catch {
      await sendLLMError(error, to: connection)
    }
  }

  private func streamResponse(
    messages: [ChatMessage],
    systemPrompt: String,
    responseFormat: ResponseFormat?,
    connection: NWConnection
  ) async {
    let id = "chatcmpl-\(UUID().uuidString.prefix(8))"

    await send(HTTP.sseHeaders, to: connection, closeAfter: false)
    await sendSSE(StreamChunk.delta(id, content: ""), to: connection)

    do {
      let fullContent = try await llmProcessor.processRequest(
        messages: messages,
        systemPrompt: systemPrompt,
        responseFormat: responseFormat
      ) { [weak self] delta in
        Task {
          await self?.sendSSE(StreamChunk.delta(id, content: delta), to: connection)
        }
      }

      lastResponse = fullContent

      await sendSSE(StreamChunk.end(id), to: connection)
      await send("data: [DONE]\n\n", to: connection, closeAfter: false)
    } catch {
      await sendSSE(StreamChunk.end(id, finishReason: "error"), to: connection)
      await send("data: [DONE]\n\n", to: connection, closeAfter: false)
    }

    connection.cancel()
  }

  // MARK: - Image Generation

  private func handleImageGeneration(
    request: HTTPRequest,
    connection: NWConnection
  ) async {
    guard let body = request.body else {
      await sendError(.badRequest, message: "Missing request body", to: connection)
      return
    }

    do {
      let imageRequest = try JSONDecoder().decode(ImageRequest.self, from: body)

      guard !imageRequest.prompt.isEmpty else {
        await sendError(.badRequest, message: "Prompt cannot be empty", to: connection)
        return
      }

      let imageDataArray = try await ImageProcessor.generateImages(
        prompt: imageRequest.prompt,
        style: imageRequest.style,
        count: imageRequest.n ?? 1
      )

      let imageResponse = ImageResponse(
        created: Int(Date().timeIntervalSince1970),
        data: imageDataArray.map { ImageResponse.ImageData(b64_json: $0.base64EncodedString()) }
      )

      await sendJSON(imageResponse, to: connection)
    } catch let error as ImageProcessorError {
      switch error {
      case .notSupported, .unavailable:
        await sendError(.serviceUnavailable, message: error.localizedDescription, to: connection)
      case .invalidStyle, .invalidCount:
        await sendError(.badRequest, message: error.localizedDescription, to: connection)
      case .conversionFailed, .generationFailed:
        await sendError(.internalError, message: error.localizedDescription, to: connection)
      }
    } catch {
      await sendError(
        .badRequest,
        message: "Invalid request format: \(error.localizedDescription)",
        to: connection
      )
    }
  }

  // MARK: - Response Helpers

  private func sendModels(to connection: NWConnection) async {
    let response = ModelsResponse(
      object: "list",
      data: [.init(
        id: "apple-intelligence",
        object: "model",
        created: Int(Date().timeIntervalSince1970),
        ownedBy: "apple"
      )]
    )
    await sendJSON(response, to: connection)
  }

  private func sendJSON(_ response: some Encodable, to connection: NWConnection) async {
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    guard let data = try? encoder.encode(response) else { return }
    await send(HTTP.json(body: data), to: connection, closeAfter: true)
  }

  private func sendSSE(_ chunk: some Encodable, to connection: NWConnection) async {
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    guard let data = try? encoder.encode(chunk),
          let json = String(data: data, encoding: .utf8)
    else { return }
    await send("data: \(json)\n\n", to: connection, closeAfter: false)
  }

  private func sendLLMError(_ error: Error, to connection: NWConnection) async {
    if let llmError = error as? LLMError {
      switch llmError {
      case .modelUnavailable:
        await sendError(.serviceUnavailable, message: "Model not available", to: connection)
      case let .invalidRequest(msg):
        await sendError(.badRequest, message: msg, to: connection)
      case let .processingFailed(msg):
        await sendError(.internalError, message: msg, to: connection)
      }
    } else {
      await sendError(.internalError, message: error.localizedDescription, to: connection)
    }
  }

  private func sendError(
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

    guard let data = try? encoder.encode(errorResponse) else {
      await send(HTTP.empty(status: error.statusCode, statusText: error.statusMessage),
                 to: connection, closeAfter: true)
      return
    }

    await send(
      HTTP.json(status: error.statusCode, statusText: error.statusMessage, body: data),
      to: connection,
      closeAfter: true
    )
  }

  private func send(
    _ text: String,
    to connection: NWConnection,
    closeAfter: Bool
  ) async {
    guard let data = text.data(using: .utf8) else { return }

    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      connection.send(content: data, completion: .contentProcessed { _ in
        if closeAfter { connection.cancel() }
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

  var statusCode: Int {
    switch self {
    case .badRequest: 400
    case .notFound: 404
    case .internalError: 500
    case .serviceUnavailable: 503
    }
  }

  var statusMessage: String {
    switch self {
    case .badRequest: "Bad Request"
    case .notFound: "Not Found"
    case .internalError: "Internal Server Error"
    case .serviceUnavailable: "Service Unavailable"
    }
  }

  var message: String {
    switch self {
    case .badRequest: "The request was malformed or invalid"
    case .notFound: "The requested resource was not found"
    case .internalError: "An internal server error occurred"
    case .serviceUnavailable: "The service is temporarily unavailable"
    }
  }

  var type: String {
    switch self {
    case .badRequest: "invalid_request_error"
    case .notFound: "not_found_error"
    case .internalError: "internal_error"
    case .serviceUnavailable: "service_unavailable_error"
    }
  }

  var code: String? {
    switch self {
    case .badRequest: "bad_request"
    case .notFound: "not_found"
    case .internalError: "internal_error"
    case .serviceUnavailable: "service_unavailable"
    }
  }
}
