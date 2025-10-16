import Foundation
@preconcurrency import FoundationModels
import Network

// MARK: - Models
//
// All shared types are now defined in SharedTypes.swift
// This ensures proper type resolution by SourceKit and Swift compiler

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
  // MARK: - Constants

  private enum Constants {
    /// Default API server port
    static let defaultPort: UInt16 = 8888

    /// Port range for random port generation
    static let portRange: ClosedRange<UInt16> = 8888 ... 9999

    /// Maximum attempts for random port generation
    static let maxRandomPortAttempts = 100

    /// Delay before starting listener after stopping
    static let listenerRestartDelay: Duration = .milliseconds(100)

    /// UserDefaults keys
    enum UserDefaultsKey {
      static let isEnabled = "APIServer.isEnabled"
      static let port = "APIServer.port"
    }
  }

  // MARK: - Properties

  private(set) var isRunning = false
  private(set) var requestCount = 0
  private(set) var lastRequest = ""
  private(set) var lastResponse = ""
  private(set) var errorMessage = ""
  private(set) var localIPAddress: String?

  var isEnabled = false {
    didSet {
      UserDefaults.standard.set(isEnabled, forKey: Constants.UserDefaultsKey.isEnabled)
      if isEnabled {
        Task { await start() }
      } else {
        stop()
      }
    }
  }

  var port: UInt16 = Constants.defaultPort {
    didSet {
      UserDefaults.standard.set(port, forKey: Constants.UserDefaultsKey.port)
      if isRunning {
        Task {
          stop()
          // Wait longer to ensure port is fully released
          try? await Task.sleep(for: .milliseconds(500))
          await start()
        }
      }
    }
  }

  private let model = SystemLanguageModel.default
  private let defaultSystemPrompt = "You are a helpful AI assistant. Provide clear, concise, and accurate responses."

  private var listener: NWListener?
  private var pathMonitor: NWPathMonitor?

  private let jsonDecoder = JSONDecoder()

  // MARK: - Initialization

  init() {
    // Restore saved port
    if let savedPort = UserDefaults.standard
      .object(forKey: Constants.UserDefaultsKey.port) as? UInt16
    {
      port = savedPort
    }

    // Start network monitoring (runs for the lifetime of the instance)
    startNetworkMonitoring()

    // Restore previous state and auto-start if enabled
    let savedState = UserDefaults.standard.bool(forKey: Constants.UserDefaultsKey.isEnabled)
    if savedState {
      Task {
        // Check if current port is available before starting
        if await isCurrentPortAvailable() {
          await MainActor.run {
            isEnabled = true
          }
        } else {
          // Port is in use, clear saved state and show error
          await MainActor.run {
            isEnabled = false
            errorMessage = "Port \(port) is in use by another instance. Please close other instances first."
          }
        }
      }
    }
  }

  // MARK: - Server Lifecycle

  nonisolated func start() async {
    // Get current port value from MainActor
    let currentPort = await MainActor.run { port }

    // Stop any existing listener first
    await MainActor.run {
      if isRunning {
        stop()
      }
    }

    // Small delay to ensure port is released
    try? await Task.sleep(for: Constants.listenerRestartDelay)

    do {
      let parameters = NWParameters.tcp
      parameters.allowLocalEndpointReuse = true
      parameters.allowFastOpen = true
      let listener = try NWListener(
        using: parameters,
        on: NWEndpoint.Port(integerLiteral: currentPort)
      )

      listener.stateUpdateHandler = { [weak self] state in
        Task { @MainActor [weak self] in
          guard let self else { return }
          switch state {
          case .ready:
            isRunning = true
            errorMessage = ""
          case let .failed(error):
            isRunning = false
            // Provide user-friendly error messages
            let errorDescription = error.localizedDescription
            if errorDescription.contains("Address already in use") {
              errorMessage = "Port \(currentPort) is already in use. Please close other instances of the app or restart your device."
            } else {
              errorMessage = "Failed to start: \(errorDescription)"
            }
          case .cancelled:
            isRunning = false
          default:
            break
          }
        }
      }

      listener.newConnectionHandler = { [weak self] connection in
        Task {
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

  func cleanup() {
    stop()
    stopNetworkMonitoring()
  }

  // MARK: - Port Management

  /// Reset port to default value (8888)
  func resetToDefaultPort() {
    port = Constants.defaultPort
  }

  /// Find and set a random available port
  func findAndSetRandomPort() async {
    for _ in 0 ..< Constants.maxRandomPortAttempts {
      let randomPort = UInt16.random(in: Constants.portRange)
      if await isPortAvailable(randomPort) {
        await MainActor.run {
          port = randomPort
        }
        return
      }
    }
    await MainActor.run {
      errorMessage = "Could not find an available port. Please try again."
    }
  }

  /// Check if a specific port is available for binding
  private nonisolated func isPortAvailable(_ testPort: UInt16) async -> Bool {
    do {
      let parameters = NWParameters.tcp
      let testListener = try NWListener(
        using: parameters,
        on: NWEndpoint.Port(integerLiteral: testPort)
      )

      let isAvailable = await withCheckedContinuation { continuation in
        testListener.stateUpdateHandler = { state in
          switch state {
          case .ready:
            testListener.cancel()
            continuation.resume(returning: true)
          case .failed:
            testListener.cancel()
            continuation.resume(returning: false)
          default:
            break
          }
        }

        // Set connection handler to satisfy NWListener API requirements
        testListener.newConnectionHandler = { connection in
          connection.cancel()
        }

        testListener.start(queue: .global())
      }

      return isAvailable
    } catch {
      return false
    }
  }

  /// Check if the current configured port is available for binding
  private nonisolated func isCurrentPortAvailable() async -> Bool {
    let currentPort = await MainActor.run { port }
    return await isPortAvailable(currentPort)
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

  private func stopNetworkMonitoring() {
    pathMonitor?.cancel()
    pathMonitor = nil
  }

  private func updateLocalIPAddress() {
    localIPAddress = NetworkInfo.localIPAddress
  }

  private nonisolated func handleConnection(_ connection: NWConnection) async {
    print("🔵 [APIServer] New connection received")
    connection.start(queue: .global())

    print("🔵 [APIServer] Waiting for request...")
    guard let rawRequest = await receiveRequest(from: connection),
          let httpRequest = HTTPRequest(rawRequest: rawRequest)
    else {
      print("❌ [APIServer] Failed to parse request")
      await sendError(.badRequest, to: connection)
      return
    }

    print("✅ [APIServer] Request parsed: \(httpRequest.method) \(httpRequest.path)")
    await processRequest(httpRequest, connection: connection)
  }

  private nonisolated func receiveRequest(from connection: NWConnection) async -> String? {
    await withCheckedContinuation { continuation in
      connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, _, _ in
        if let data, let request = String(data: data, encoding: .utf8) {
          continuation.resume(returning: request)
        } else {
          continuation.resume(returning: nil)
        }
      }
    }
  }

  private nonisolated func processRequest(_ request: HTTPRequest, connection: NWConnection) async {
    print("🟢 [APIServer] processRequest called: \(request.method) \(request.path)")

    switch (request.method, request.path) {
    case ("GET", "/v1/models"):
      print("🟢 [APIServer] Routing to sendModels")
      await sendModels(to: connection)

    case ("POST", "/v1/chat/completions"):
      print("🟢 [APIServer] Routing to handleChatCompletion")
      await handleChatCompletion(request: request, connection: connection)

    default:
      print("❌ [APIServer] Unknown route: \(request.method) \(request.path)")
      await sendError(.notFound, to: connection)
    }

    print("🟢 [APIServer] processRequest completed")
  }

  private nonisolated func handleChatCompletion(
    request: HTTPRequest,
    connection: NWConnection
  ) async {
    print("🟡 [APIServer] handleChatCompletion called")

    guard let body = request.body else {
      print("❌ [APIServer] Missing request body")
      await sendError(.badRequest, message: "Missing request body", to: connection)
      return
    }

    print("🟡 [APIServer] Body size: \(body.count) bytes")
    print("🟡 [APIServer] Decoding ChatRequest...")

    do {
      let chatRequest = try await MainActor.run {
        try jsonDecoder.decode(ChatRequest.self, from: body)
      }

      print("✅ [APIServer] ChatRequest decoded successfully")
      print("🟡 [APIServer] Messages count: \(chatRequest.messages.count)")
      print("🟡 [APIServer] Stream: \(chatRequest.stream ?? false)")

      guard !chatRequest.messages.isEmpty else {
        print("❌ [APIServer] Messages array is empty")
        await sendError(.badRequest, message: "Messages array cannot be empty", to: connection)
        return
      }

      // Extract system prompt from messages
      let systemPrompt = chatRequest.messages.first(where: { $0.role == "system" })?
        .content ?? defaultSystemPrompt
      print("🟡 [APIServer] System prompt: \(systemPrompt.prefix(50))...")

      // Get conversation messages (excluding system)
      let conversationMessages = chatRequest.messages.filter { $0.role != "system" }
      print("🟡 [APIServer] Conversation messages: \(conversationMessages.count)")

      guard let lastUserMessage = conversationMessages.last(where: { $0.role == "user" }) else {
        print("❌ [APIServer] No user message found")
        await sendError(.badRequest, message: "No user message found", to: connection)
        return
      }

      print("🟡 [APIServer] Last user message: \(lastUserMessage.content)")

      await MainActor.run {
        self.requestCount += 1
        self.lastRequest = lastUserMessage.content
      }

      if chatRequest.stream == true {
        print("🟡 [APIServer] Using streaming response")
        await streamResponse(
          messages: conversationMessages,
          systemPrompt: systemPrompt,
          responseFormat: chatRequest.response_format,
          connection: connection
        )
      } else {
        print("🟡 [APIServer] Using non-streaming response")
        await sendResponse(
          messages: conversationMessages,
          systemPrompt: systemPrompt,
          responseFormat: chatRequest.response_format,
          connection: connection
        )
      }

      print("✅ [APIServer] handleChatCompletion completed")
    } catch {
      print("❌ [APIServer] Decode error: \(error.localizedDescription)")
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
    print("📥 [APIServer] sendResponse called")
    print("📥 [APIServer] Model availability: \(model.availability)")

    guard case .available = model.availability else {
      print("❌ [APIServer] Model not available!")
      await sendError(.serviceUnavailable, message: "Model not available", to: connection)
      return
    }

    do {
      guard let lastMessage = messages.last, lastMessage.role == "user" else {
        print("❌ [APIServer] Last message is not from user")
        await sendError(.badRequest, message: "Last message must be from user", to: connection)
        return
      }

      print("🔄 [APIServer] Building transcript...")
      let transcript = buildTranscript(
        from: messages,
        systemPrompt: systemPrompt
      )

      print("🔄 [APIServer] Creating LanguageModelSession...")
      let session = LanguageModelSession(transcript: transcript)

      // Convert JSON Schema to Apple schema if needed
      let content: String
      if let responseFormat,
         responseFormat.type == "json_schema",
         let jsonSchema = responseFormat.json_schema
      {
        print("🔄 [APIServer] Converting JSON schema...")
        let validatedSchema = try await MainActor.run {
          let converter = SchemaConverter()
          return try converter.convert(jsonSchema)
        }
        print("🔄 [APIServer] Calling session.respond() with schema...")
        let response = try await session.respond(to: lastMessage.content, schema: validatedSchema)
        content = response.content.jsonString
        print("✅ [APIServer] Got response with schema: \(content.prefix(100))...")
      } else {
        print("🔄 [APIServer] Calling session.respond() without schema...")
        print("🔄 [APIServer] User message: \(lastMessage.content)")
        let response = try await session.respond(to: lastMessage.content)
        content = response.content
        print("✅ [APIServer] Got response: \(content.prefix(100))...")
      }

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

      print("📤 [APIServer] Sending response to client...")
      await send(chatResponse, to: connection)
      print("✅ [APIServer] Response sent successfully")
    } catch {
      let errorMessage = error.localizedDescription
      print("❌ [APIServer] Error: \(errorMessage)")
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

  private nonisolated func buildTranscript(
    from messages: [ChatMessage],
    systemPrompt: String
  ) -> Transcript {
    var entries: [Transcript.Entry] = []

    let instructions = Transcript.Instructions(
      segments: [.text(.init(content: systemPrompt))],
      toolDefinitions: []
    )
    entries.append(.instructions(instructions))

    for message in messages {
      switch message.role {
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

  private nonisolated func streamResponse(
    messages: [ChatMessage],
    systemPrompt: String,
    responseFormat: ResponseFormat?,
    connection: NWConnection
  ) async {
    print("🌊 [APIServer] streamResponse called")
    print("🌊 [APIServer] Model availability: \(model.availability)")

    guard case .available = model.availability else {
      print("❌ [APIServer] Model not available for streaming")
      await sendError(.serviceUnavailable, message: "Model not available", to: connection)
      return
    }

    let id = "chatcmpl-\(UUID().uuidString.prefix(8))"
    let timestamp = Int(Date().timeIntervalSince1970)
    var fullContent = ""
    var previousContent = ""

    print("🌊 [APIServer] Sending stream headers...")
    await sendStreamHeaders(to: connection)
    print("✅ [APIServer] Stream headers sent")

    let initialChunk = StreamChunk(
      id: id,
      object: "chat.completion.chunk",
      created: timestamp,
      model: "apple-intelligence",
      choices: [.init(index: 0, delta: .init(role: "assistant", content: ""), finishReason: nil)]
    )
    print("🌊 [APIServer] Sending initial chunk...")
    await sendStreamChunk(initialChunk, to: connection)
    print("✅ [APIServer] Initial chunk sent")

    do {
      guard let lastMessage = messages.last, lastMessage.role == "user" else {
        let errorChunk = StreamChunk(
          id: id,
          object: "chat.completion.chunk",
          created: timestamp,
          model: "apple-intelligence",
          choices: [.init(
            index: 0,
            delta: .init(role: "assistant", content: "Error: Last message must be from user"),
            finishReason: "error"
          )]
        )
        await sendStreamChunk(errorChunk, to: connection)
        await sendStreamEnd(to: connection)
        connection.cancel()
        return
      }

      print("🌊 [APIServer] Building transcript...")
      let transcript = buildTranscript(
        from: messages,
        systemPrompt: systemPrompt
      )
      print("✅ [APIServer] Transcript built")

      print("🌊 [APIServer] Creating LanguageModelSession...")
      let session = LanguageModelSession(transcript: transcript)
      print("✅ [APIServer] LanguageModelSession created")

      // Convert JSON Schema to Apple schema if needed
      if let responseFormat,
         responseFormat.type == "json_schema",
         let jsonSchema = responseFormat.json_schema
      {
        print("🌊 [APIServer] Converting JSON schema...")
        let validatedSchema = try await MainActor.run {
          let converter = SchemaConverter()
          return try converter.convert(jsonSchema)
        }
        print("✅ [APIServer] Schema converted")
        print("🌊 [APIServer] Calling session.streamResponse() with schema...")
        let stream = session.streamResponse(to: lastMessage.content, schema: validatedSchema)
        print("✅ [APIServer] Got stream object")

        print("🌊 [APIServer] Starting to iterate stream with schema...")
        for try await snapshot in stream {
          print("🌊 [APIServer] Got snapshot from stream")
          fullContent = snapshot.content.jsonString
          let delta = String(fullContent.dropFirst(previousContent.count))

          if !delta.isEmpty {
            print("🌊 [APIServer] Sending delta: \(delta.prefix(50))...")
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
            await sendStreamChunk(chunk, to: connection)
          }

          previousContent = fullContent
        }
        print("✅ [APIServer] Stream iteration completed (with schema)")
      } else {
        print("🌊 [APIServer] Calling session.streamResponse() without schema...")
        let stream = session.streamResponse(to: lastMessage.content)
        print("✅ [APIServer] Got stream object")
        print("🌊 [APIServer] Starting to iterate stream...")

        for try await snapshot in stream {
          print("🌊 [APIServer] Got snapshot from stream")
          fullContent = snapshot.content
          let delta = String(fullContent.dropFirst(previousContent.count))

          if !delta.isEmpty {
            print("🌊 [APIServer] Sending delta: \(delta.prefix(50))...")
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
            await sendStreamChunk(chunk, to: connection)
          }

          previousContent = fullContent
        }
        print("✅ [APIServer] Stream iteration completed")
      }

      let finalContent = fullContent
      await MainActor.run {
        self.lastResponse = finalContent
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
    } catch {
      let errorMessage = error.localizedDescription
      let errorContent = if errorMessage.contains("context") || errorMessage.contains("window") {
        "Error: Context window exceeded. Please start a new conversation."
      } else {
        "Error: \(errorMessage)"
      }

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
    // Create local encoder for thread-safe encoding without MainActor
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase

    // Encode in a nonisolated context
    guard let data = try? encoder.encode(response),
          let json = String(data: data, encoding: .utf8)
    else {
      return
    }

    // 打印响应日志
    await logResponse(json)

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

  private nonisolated func logResponse(_ json: String) async {
    print("\n" + String(repeating: "-", count: 80))
    print("📤 Outgoing API Response")
    print(String(repeating: "-", count: 80))
    print("🔹 Timestamp: \(Date())")
    print("\n📦 Response Body:")

    // Try to format JSON for better readability
    if let jsonData = json.data(using: .utf8),
       let jsonObject = try? JSONSerialization.jsonObject(with: jsonData),
       let prettyData = try? JSONSerialization.data(
         withJSONObject: jsonObject,
         options: [.prettyPrinted, .sortedKeys]
       ),
       let prettyString = String(data: prettyData, encoding: .utf8)
    {
      print(prettyString)
    } else {
      print(json)
    }

    print(String(repeating: "-", count: 80) + "\n")
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
    // Create local encoder for thread-safe encoding without MainActor
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase

    guard let data = try? encoder.encode(chunk),
          let json = String(data: data, encoding: .utf8)
    else {
      return
    }

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

    // Create local encoder for thread-safe encoding without MainActor
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

    let dataCount = data.count

    let httpResponse = """
    HTTP/1.1 \(error.statusCode) \(error.statusMessage)\r
    Content-Type: application/json\r
    Content-Length: \(dataCount)\r
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
    guard let data = text.data(using: .utf8) else {
      print("❌ [APIServer] Failed to convert text to data")
      return
    }

    print("📤 [APIServer] Sending \(data.count) bytes, closeAfter: \(closeAfter)")
    print("📤 [APIServer] Connection state: \(connection.state)")

    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      connection.send(content: data, completion: .contentProcessed { error in
        if let error {
          print("❌ [APIServer] Send error: \(error)")
        } else {
          print("✅ [APIServer] Send completed successfully")
        }

        if closeAfter {
          connection.cancel()
        }
        continuation.resume()
      })
    }

    print("✅ [APIServer] send() method completed")
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
