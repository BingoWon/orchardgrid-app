import Foundation
@preconcurrency import FoundationModels
import Network
import OrchardGridCore

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
  /// Permissive CORS — the local server is a LAN tool, browser clients are
  /// expected. A trailing CRLF is baked in so it slots between header lines.
  static let corsHeaders = """
    Access-Control-Allow-Origin: *\r
    Access-Control-Allow-Methods: GET, POST, OPTIONS\r
    Access-Control-Allow-Headers: Content-Type, Authorization\r

    """

  static func json(status: Int = 200, body: Data) -> String {
    let json = String(data: body, encoding: .utf8) ?? ""
    return """
      HTTP/1.1 \(status) \(httpStatusText(status))\r
      Content-Type: application/json\r
      Content-Length: \(body.count)\r
      \(corsHeaders)\
      Connection: close\r
      \r
      \(json)
      """
  }

  static let sseHeaders = """
    HTTP/1.1 200 OK\r
    Content-Type: text/event-stream\r
    Cache-Control: no-cache\r
    \(corsHeaders)\
    Connection: keep-alive\r
    \r

    """

  static let corsPreflight = """
    HTTP/1.1 204 No Content\r
    \(corsHeaders)\
    Connection: close\r
    \r

    """

  static func empty(status: Int) -> String {
    """
    HTTP/1.1 \(status) \(httpStatusText(status))\r
    \(corsHeaders)\
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
  private(set) var lastError: APIError?
  private(set) var localIPAddress: String?
  private(set) var portConflict = false
  private(set) var suggestedPort: UInt16?

  private(set) var port: UInt16 = Config.apiServerPort

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

  /// Optional Bearer token. When set, clients must send
  /// `Authorization: Bearer <token>` on every request except CORS preflight
  /// and `GET /health`. Sourced from env `ORCHARDGRID_API_TOKEN` or
  /// UserDefaults key `APIServer.authToken`.
  private let authToken: String?

  private typealias Handler = @MainActor (Data) async throws -> Data

  private let capabilityRoutes: [String: Handler]
  private var enabledCapabilities: Set<Capability> = Set(Capability.allCases)

  private static let routeToCapability: [String: Capability] = [
    "/v1/chat/completions": .chat,
    "/v1/images/generations": .image,
    "/v1/nlp/analyze": .nlp,
    "/v1/vision/analyze": .vision,
    "/v1/audio/transcriptions": .speech,
    "/v1/audio/classify": .sound,
  ]

  private static let routeHandlers: [(path: String, available: Bool, handler: Handler)] = [
    (
      "/v1/images/generations", ImageProcessor.isAvailable,
      { data in try await ImageProcessor.handle(data) }
    ),
    ("/v1/nlp/analyze", NLPProcessor.isAvailable, { data in try await NLPProcessor.handle(data) }),
    (
      "/v1/vision/analyze", VisionProcessor.isAvailable,
      { data in try await VisionProcessor.handle(data) }
    ),
    (
      "/v1/audio/transcriptions", SpeechProcessor.isAvailable,
      { data in try await SpeechProcessor.handle(data) }
    ),
    (
      "/v1/audio/classify", SoundProcessor.isAvailable,
      { data in try await SoundProcessor.handle(data) }
    ),
  ]

  // MARK: - Initialization

  init(llmProcessor: LLMProcessor) {
    self.llmProcessor = llmProcessor
    // Auth token: env wins, then App Group (so the user can configure it
    // via Settings or `defaults write`), then nil (no auth required).
    self.authToken =
      ProcessInfo.processInfo.environment["ORCHARDGRID_API_TOKEN"]
      ?? OGSharedDefaults.store.string(forKey: OGSharedDefaults.Key.apiServerAuthToken)

    var routes: [String: Handler] = [:]
    for (path, available, handler) in Self.routeHandlers where available {
      routes[path] = handler
    }
    capabilityRoutes = routes
    startNetworkMonitoring()
  }

  /// Publish runtime state to the App Group so `og status` (and any other
  /// peer process) can read it. Called whenever isRunning or port changes.
  private func publishState() {
    let store = OGSharedDefaults.store
    store.set(isRunning, forKey: OGSharedDefaults.Key.localRunning)
    store.set(Int(port), forKey: OGSharedDefaults.Key.localPort)
  }

  // MARK: - Capability Management

  func updateEnabledCapabilities(_ caps: Set<Capability>) {
    enabledCapabilities = caps
  }

  // MARK: - Server Lifecycle

  func start() async {
    guard !isRunning else { return }
    portConflict = false
    suggestedPort = nil

    do {
      let parameters = NWParameters.tcp
      parameters.allowLocalEndpointReuse = true
      let listener = try NWListener(using: parameters, on: NWEndpoint.Port(integerLiteral: port))

      listener.stateUpdateHandler = { [weak self] state in
        Task { @MainActor [weak self] in
          guard let self else { return }
          switch state {
          case .ready:
            self.isRunning = true
            self.lastError = nil
            self.portConflict = false
          case .failed(let nwError):
            self.isRunning = false
            if case .posix(let code) = nwError, code == .EADDRINUSE {
              self.portConflict = true
              self.lastError = .local(
                String(localized: "Port \(self.port) is already in use."))
              self.suggestedPort = Self.findAvailablePort(from: self.port &+ 1)
            } else {
              self.lastError = .local(nwError.localizedDescription)
            }
          case .cancelled:
            self.isRunning = false
          default:
            break
          }
          self.publishState()
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
      lastError = APIError.classify(error)
    }
  }

  func setPort(_ newPort: UInt16) {
    stop()
    port = newPort
    portConflict = false
    suggestedPort = nil
    lastError = nil
    publishState()
    if isEnabled {
      Task { await start() }
    }
  }

  nonisolated static func findAvailablePort(from start: UInt16, range: UInt16 = 20) -> UInt16? {
    for offset: UInt16 in 0..<range {
      let candidate = start &+ offset
      if isPortAvailable(candidate) { return candidate }
    }
    return nil
  }

  nonisolated static func isPortAvailable(_ port: UInt16) -> Bool {
    let fd = socket(AF_INET6, SOCK_STREAM, IPPROTO_TCP)
    guard fd >= 0 else { return false }
    defer { Darwin.close(fd) }

    var addr = sockaddr_in6()
    addr.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
    addr.sin6_family = sa_family_t(AF_INET6)
    addr.sin6_port = port.bigEndian
    addr.sin6_addr = in6addr_any

    return withUnsafePointer(to: &addr) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in6>.size))
      }
    } == 0
  }

  func stop() {
    listener?.cancel()
    listener = nil
    isRunning = false
    lastError = nil
    portConflict = false
    suggestedPort = nil
    publishState()
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
    var buffer = Data()

    while buffer.count < Config.maxRequestSize {
      let (chunk, isComplete) = await receiveChunk(from: connection)
      if let chunk { buffer.append(chunk) }
      if isComplete || chunk == nil { break }

      if let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) {
        let headers = String(data: buffer[..<headerEnd.lowerBound], encoding: .utf8) ?? ""
        let bodyStart = buffer.distance(from: buffer.startIndex, to: headerEnd.upperBound)

        if let line = headers.lowercased().split(separator: "\r\n")
          .first(where: { $0.hasPrefix("content-length:") }),
          let cl = Int(line.split(separator: ":").last?.trimmingCharacters(in: .whitespaces) ?? "")
        {
          if buffer.count - bodyStart >= cl { break }
        } else {
          break
        }
      }
    }

    return buffer.isEmpty ? nil : String(data: buffer, encoding: .utf8)
  }

  private func receiveChunk(from connection: NWConnection) async -> (Data?, Bool) {
    await withCheckedContinuation { continuation in
      connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) {
        data, _, isComplete, _ in
        continuation.resume(returning: (data, isComplete))
      }
    }
  }

  private func processRequest(_ request: HTTPRequest, connection: NWConnection) async {
    // Auth: required for everything except CORS preflight and /health.
    let isOpenRoute =
      request.method == "OPTIONS"
      || (request.method == "GET" && request.path == "/health")
    if let expected = authToken, !isOpenRoute, !isAuthorized(request, expected: expected) {
      await sendError(.unauthorized, to: connection)
      return
    }

    if let capability = Self.routeToCapability[request.path],
      !enabledCapabilities.contains(capability)
    {
      await sendError(
        .serviceUnavailable, message: "\(capability.displayName) is disabled", to: connection)
      return
    }

    switch (request.method, request.path) {
    case ("OPTIONS", _):
      await send(HTTP.corsPreflight, to: connection, closeAfter: true)

    case ("GET", "/health"):
      await sendHealth(to: connection)

    case ("GET", "/v1/models"):
      await sendModels(to: connection)

    case ("POST", "/v1/chat/completions"):
      await handleChatCompletion(request: request, connection: connection)

    case ("POST", let path) where capabilityRoutes[path] != nil:
      await handleGenericCapability(path: path, request: request, connection: connection)

    default:
      await sendError(.notFound, to: connection)
    }
  }

  private func isAuthorized(_ request: HTTPRequest, expected: String) -> Bool {
    guard
      let header = request.headers.first(where: {
        $0.key.caseInsensitiveCompare("Authorization") == .orderedSame
      })?.value,
      header.hasPrefix("Bearer ")
    else { return false }
    return String(header.dropFirst(7)) == expected
  }

  // MARK: - Generic Capability Handler

  private func handleGenericCapability(
    path: String,
    request: HTTPRequest,
    connection: NWConnection
  ) async {
    guard let handler = capabilityRoutes[path] else {
      await sendError(.notFound, to: connection)
      return
    }

    guard let body = request.body else {
      await sendError(.badRequest, message: "Missing request body", to: connection)
      return
    }

    requestCount += 1

    do {
      let result = try await handler(body)
      await send(HTTP.json(body: result), to: connection, closeAfter: true)
    } catch {
      await sendError(.internalError, message: error.localizedDescription, to: connection)
    }
  }

  // MARK: - Chat Completion (special: supports streaming)

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

      let messages = chatRequest.nonSystemMessages

      guard messages.last(where: { $0.role == "user" }) != nil else {
        await sendError(.badRequest, message: "No user message found", to: connection)
        return
      }

      requestCount += 1

      if chatRequest.stream == true {
        await streamResponse(
          messages: messages,
          systemPrompt: chatRequest.systemPrompt,
          responseFormat: chatRequest.responseFormat,
          options: chatRequest.sessionOptions,
          connection: connection
        )
      } else {
        await sendChatResponse(
          messages: messages,
          systemPrompt: chatRequest.systemPrompt,
          responseFormat: chatRequest.responseFormat,
          options: chatRequest.sessionOptions,
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
    options: SessionOptions,
    connection: NWConnection
  ) async {
    do {
      let result = try await llmProcessor.processRequest(
        messages: messages,
        systemPrompt: systemPrompt,
        responseFormat: responseFormat,
        options: options
      )
      await sendJSON(
        ChatResponse.create(
          content: result.content,
          promptTokens: result.promptTokens,
          completionTokens: result.completionTokens
        ),
        to: connection
      )
    } catch {
      await sendLLMError(error, to: connection)
    }
  }

  private func streamResponse(
    messages: [ChatMessage],
    systemPrompt: String,
    responseFormat: ResponseFormat?,
    options: SessionOptions,
    connection: NWConnection
  ) async {
    let id = "chatcmpl-\(UUID().uuidString.prefix(8))"
    await send(HTTP.sseHeaders, to: connection, closeAfter: false)
    await sendSSE(StreamChunk.delta(id, content: ""), to: connection)

    do {
      let result = try await llmProcessor.processRequest(
        messages: messages,
        systemPrompt: systemPrompt,
        responseFormat: responseFormat,
        options: options
      ) { [weak self] delta in
        Task {
          await self?.sendSSE(StreamChunk.delta(id, content: delta), to: connection)
        }
      }
      let usage = TokenUsage(
        promptTokens: result.promptTokens,
        completionTokens: result.completionTokens,
        totalTokens: result.totalTokens
      )
      await sendSSE(StreamChunk.end(id, usage: usage), to: connection)
      await send("data: [DONE]\n\n", to: connection, closeAfter: false)
    } catch {
      await sendSSE(StreamChunk.end(id, finishReason: "error"), to: connection)
      await send("data: [DONE]\n\n", to: connection, closeAfter: false)
    }
    connection.cancel()
  }

  // MARK: - Response Helpers

  private func sendHealth(to connection: NWConnection) async {
    struct HealthResponse: Encodable {
      let status: String
      let model: String
      let available: Bool
    }
    await sendJSON(
      HealthResponse(
        status: "ok", model: AppIdentity.modelName, available: llmProcessor.isAvailable),
      to: connection
    )
  }

  private func sendModels(to connection: NWConnection) async {
    let now = Int(Date().timeIntervalSince1970)
    var models: [ModelsResponse.Model] = []

    if enabledCapabilities.contains(.chat), llmProcessor.isAvailable {
      models.append(
        .init(id: AppIdentity.modelName, object: "model", created: now, ownedBy: "apple"))
    }

    for (path, capability) in Self.routeToCapability {
      guard enabledCapabilities.contains(capability), capabilityRoutes[path] != nil else {
        continue
      }
      models.append(
        .init(
          id: "\(AppIdentity.modelName)-\(capability.rawValue)", object: "model", created: now,
          ownedBy: "apple"))
    }

    await sendJSON(ModelsResponse(object: "list", data: models), to: connection)
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
    let llmError = LLMError.classify(error)
    await sendErrorJSON(
      status: llmError.httpStatusCode,
      message: llmError.errorDescription ?? "Unknown error",
      type: llmError.openAIType,
      code: nil,
      to: connection
    )
  }

  private func sendError(
    _ error: HTTPError,
    message: String? = nil,
    to connection: NWConnection
  ) async {
    await sendErrorJSON(
      status: error.statusCode,
      message: message ?? error.message,
      type: error.type,
      code: error.code,
      to: connection
    )
  }

  /// Shared error-response writer. Falls back to a header-only response if
  /// JSON encoding fails (shouldn't happen in practice — defensive).
  private func sendErrorJSON(
    status: Int,
    message: String,
    type: String,
    code: String?,
    to connection: NWConnection
  ) async {
    let body = ErrorResponse(error: .init(message: message, type: type, code: code))
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    if let data = try? encoder.encode(body) {
      await send(HTTP.json(status: status, body: data), to: connection, closeAfter: true)
    } else {
      await send(HTTP.empty(status: status), to: connection, closeAfter: true)
    }
  }

  private func send(
    _ text: String,
    to connection: NWConnection,
    closeAfter: Bool
  ) async {
    guard let data = text.data(using: .utf8) else { return }

    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      connection.send(
        content: data,
        completion: .contentProcessed { _ in
          if closeAfter { connection.cancel() }
          continuation.resume()
        })
    }
  }
}

// MARK: - HTTP Error

enum HTTPError: Sendable {
  case badRequest
  case unauthorized
  case notFound
  case internalError
  case serviceUnavailable

  var statusCode: Int {
    switch self {
    case .badRequest: 400
    case .unauthorized: 401
    case .notFound: 404
    case .internalError: 500
    case .serviceUnavailable: 503
    }
  }

  var message: String {
    switch self {
    case .badRequest: "The request was malformed or invalid"
    case .unauthorized: "Authentication required"
    case .notFound: "The requested resource was not found"
    case .internalError: "An internal server error occurred"
    case .serviceUnavailable: "The service is temporarily unavailable"
    }
  }

  var type: String {
    switch self {
    case .badRequest: "invalid_request_error"
    case .unauthorized: "authentication_error"
    case .notFound: "not_found_error"
    case .internalError: "internal_error"
    case .serviceUnavailable: "service_unavailable_error"
    }
  }

  var code: String? {
    switch self {
    case .badRequest: "bad_request"
    case .unauthorized: "unauthorized"
    case .notFound: "not_found"
    case .internalError: "internal_error"
    case .serviceUnavailable: "service_unavailable"
    }
  }
}
