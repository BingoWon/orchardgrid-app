import Foundation
@preconcurrency import FoundationModels
import Network

@Observable
@MainActor
final class WebSocketClient: NSObject, URLSessionWebSocketDelegate {
  // MARK: - Configuration

  private let serverURL: String
  private let hardwareID: String
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
      if isEnabled { startConnection() } else { stopConnection() }
    }
  }

  // MARK: - Private State

  private var tokenProvider: (@Sendable () async -> String?)?
  private var webSocketTask: URLSessionWebSocketTask?
  private var urlSession: URLSession?
  private var connectionTask: Task<Void, Never>?
  private var heartbeatTask: Task<Void, Never>?
  private let networkMonitor = NWPathMonitor()
  private var isNetworkAvailable = true
  private var lastHeartbeatResponse: Date?

  // MARK: - Capability Handlers

  private let llmProcessor: LLMProcessor
  private var handlers: [Capability: @MainActor (Data) async throws -> Data] = [:]
  private var enabledCapabilities: Set<Capability> = Set(Capability.allCases)

  private var activeCapabilityNames: [String] {
    handlers.keys.map(\.rawValue).sorted()
  }

  // MARK: - Initialization

  init(llmProcessor: LLMProcessor) {
    self.llmProcessor = llmProcessor

    serverURL = ProcessInfo.processInfo.environment["ORCHARDGRID_SERVER_URL"]
      ?? "\(Config.webSocketBaseURL)/device/connect"

    hardwareID = DeviceInfo.hardwareID

    #if os(macOS)
      platform = "macOS"
    #elseif os(iOS)
      platform = "iOS"
    #else
      platform = "unknown"
    #endif

    osVersion = ProcessInfo.processInfo.operatingSystemVersionString

    super.init()
    registerCapabilities()
    startNetworkMonitoring()
  }

  deinit {
    networkMonitor.cancel()
  }

  // MARK: - Capability Management

  func updateEnabledCapabilities(_ caps: Set<Capability>) {
    let oldCaps = Set(handlers.keys)
    enabledCapabilities = caps
    registerCapabilities()
    let newCaps = Set(handlers.keys)

    if oldCaps != newCaps, isConnected {
      Logger.log(.websocket, "Capabilities changed, reconnecting...")
      stopConnection()
      if isEnabled { startConnection() }
    }
  }

  // MARK: - Capability Registration

  private func registerCapabilities() {
    handlers.removeAll()

    if enabledCapabilities.contains(.chat), llmProcessor.isAvailable {
      handlers[.chat] = { [weak self] data in
        guard let self else { throw CapabilityError.unavailable }
        let req = try JSONDecoder().decode(ChatRequest.self, from: data)
        let content = try await self.processChat(req)
        let tokens = self.estimateTokens(req.messages)
        return try JSONEncoder().encode(ChatResponse.create(content: content, promptTokens: tokens))
      }
    }

    let staticHandlers: [(Capability, Bool, @MainActor @Sendable (Data) async throws -> Data)] = [
      (.image, ImageProcessor.isAvailable, { data in try await ImageProcessor.handle(data) }),
      (.translate, TranslationProcessor.isAvailable, { data in try await TranslationProcessor.handle(data) }),
      (.nlp, NLPProcessor.isAvailable, { data in try await NLPProcessor.handle(data) }),
      (.vision, VisionProcessor.isAvailable, { data in try await VisionProcessor.handle(data) }),
      (.speech, SpeechProcessor.isAvailable, { data in try await SpeechProcessor.handle(data) }),
      (.sound, SoundProcessor.isAvailable, { data in try await SoundProcessor.handle(data) }),
    ]

    for (capability, available, handler) in staticHandlers
      where enabledCapabilities.contains(capability) && available
    {
      handlers[capability] = handler
    }
  }

  // MARK: - Auth API

  func setAuth(tokenProvider: @escaping @Sendable () async -> String?) {
    self.tokenProvider = tokenProvider
    Logger.log(.websocket, "Auth configured")

    guard isEnabled else { return }

    if isConnected {
      Logger.log(.websocket, "Reconnecting with new auth...")
      stopConnection()
    }
    startConnection()
  }

  func clearAuth() {
    guard tokenProvider != nil else { return }
    Logger.log(.websocket, "Auth cleared")
    tokenProvider = nil

    guard isEnabled else { return }
    Logger.log(.websocket, "Reconnecting anonymously...")
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
      defer { connectionTask = nil }

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
      URLQueryItem(name: "capabilities", value: activeCapabilityNames.joined(separator: ",")),
    ]

    if let token = await tokenProvider?() {
      queryItems.insert(URLQueryItem(name: "token", value: token), at: 0)
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
    configuration.timeoutIntervalForRequest = Config.connectionRequestTimeout
    configuration.timeoutIntervalForResource = 0
    configuration.waitsForConnectivity = true
    configuration.networkServiceType = .responsiveData
    urlSession = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)

    webSocketTask = urlSession?.webSocketTask(with: url)
    webSocketTask?.resume()
    receiveMessage()

    let deadline = Date().addingTimeInterval(Config.connectionTimeout)
    while !Task.isCancelled, Date() < deadline {
      if isConnected { return true }
      if case .failed = connectionState { return false }
      try? await Task.sleep(for: .milliseconds(100))
    }

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
      if isEnabled, isNetworkAvailable, connectionTask == nil {
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
      if nsError.domain == NSURLErrorDomain, nsError.code == -999 { return }

      Logger.error(.websocket, "Connection error: \(error.localizedDescription)")
      connectionState = .failed(error.localizedDescription)

      if isEnabled, isNetworkAvailable, connectionTask == nil {
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
          if nsError.domain == NSURLErrorDomain, nsError.code == -999 { return }

          Logger.error(.websocket, "Receive error: \(error.localizedDescription)")
          self.connectionState = .disconnected

          if self.isEnabled, self.isNetworkAvailable, self.connectionTask == nil {
            self.startConnection()
          }
        }
      }
    }
  }

  private func handleMessage(_ text: String) async {
    guard let data = text.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      Logger.error(.websocket, "Failed to parse message JSON")
      return
    }

    if let type = json["type"] as? String, type == "heartbeat" || type == "pong" {
      lastHeartbeatResponse = Date()
      return
    }

    guard let id = json["id"] as? String,
          let capabilityStr = json["capability"] as? String,
          let capability = Capability(rawValue: capabilityStr),
          let payloadObj = json["payload"]
    else { return }

    let stream = (json["stream"] as? Bool) ?? false
    let payloadData: Data
    do {
      payloadData = try JSONSerialization.data(withJSONObject: payloadObj)
    } catch {
      Logger.error(.websocket, "Failed to serialize payload")
      return
    }

    Logger.log(.websocket, "Task \(id.prefix(8)): \(capability.rawValue)\(stream ? " [stream]" : "")")

    if capability == .chat, stream {
      await handleStreamingChat(id: id, payload: payloadData)
    } else {
      await handleCapabilityTask(id: id, capability: capability, payload: payloadData)
    }
  }

  // MARK: - Unified Task Dispatch

  private func handleCapabilityTask(id: String, capability: Capability, payload: Data) async {
    guard let handler = handlers[capability] else {
      await sendError(id: id, error: "Unsupported capability: \(capability.rawValue)")
      return
    }

    let start = Date()
    do {
      let result = try await handler(payload)
      await sendResponse(id: id, payload: result)
      tasksProcessed += 1
      let duration = Date().timeIntervalSince(start)
      Logger.success(.websocket, "\(capability.rawValue) task \(id.prefix(8)) completed in \(String(format: "%.2f", duration))s")
    } catch {
      Logger.error(.websocket, "\(capability.rawValue) task \(id.prefix(8)) failed: \(error)")
      await sendError(id: id, error: error.localizedDescription)
    }
  }

  private func handleStreamingChat(id: String, payload: Data) async {
    let start = Date()
    do {
      let req = try JSONDecoder().decode(ChatRequest.self, from: payload)
      let content = try await processChat(req) { [weak self] delta in
        Task { await self?.sendStreamDelta(id: id, delta: delta) }
      }
      await sendStreamEnd(id: id)
      tasksProcessed += 1
      let duration = Date().timeIntervalSince(start)
      Logger.success(.websocket, "chat stream \(id.prefix(8)) completed in \(String(format: "%.2f", duration))s")
    } catch {
      Logger.error(.websocket, "chat stream \(id.prefix(8)) failed: \(error)")
      await sendError(id: id, error: error.localizedDescription)
    }
  }

  // MARK: - Chat Processing

  private func processChat(
    _ request: ChatRequest,
    onChunk: ((String) -> Void)? = nil
  ) async throws -> String {
    let systemPrompt = request.messages.first { $0.role == "system" }?.content
      ?? Config.defaultSystemPrompt
    let messages = request.messages.filter { $0.role != "system" }
    return try await llmProcessor.processRequest(
      messages: messages,
      systemPrompt: systemPrompt,
      responseFormat: request.response_format,
      onChunk: onChunk
    )
  }

  private func estimateTokens(_ messages: [ChatMessage]) -> Int {
    max(1, messages.reduce(0) { $0 + $1.content.count } / 4)
  }

  // MARK: - Heartbeat

  private func startHeartbeat() {
    stopHeartbeat()
    heartbeatTask = Task { @MainActor in
      while !Task.isCancelled, isConnected {
        try? await Task.sleep(for: .seconds(Config.heartbeatInterval))
        guard isConnected else { return }

        if let lastResponse = lastHeartbeatResponse,
           Date().timeIntervalSince(lastResponse) > Config.heartbeatTimeout
        {
          Logger.error(.websocket, "Heartbeat timeout — connection appears dead")
          connectionState = .disconnected
          stopHeartbeat()
          if isEnabled, isNetworkAvailable {
            startConnection()
          }
          return
        }

        await sendJSON(["type": "heartbeat"])
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
          if isEnabled, !isConnected { startConnection() }
        } else if wasAvailable, !isNetworkAvailable {
          Logger.log(.websocket, "Network lost")
        }
      }
    }
    networkMonitor.start(queue: .global(qos: .utility))
  }

  // MARK: - Message Sending

  private func sendResponse(id: String, payload: Data) async {
    guard let payloadObj = try? JSONSerialization.jsonObject(with: payload) else { return }
    await sendJSON(["id": id, "type": "response", "payload": payloadObj])
  }

  private func sendStreamDelta(id: String, delta: String) async {
    await sendJSON(["id": id, "type": "stream", "delta": delta])
  }

  private func sendStreamEnd(id: String) async {
    await sendJSON(["id": id, "type": "stream_end"])
  }

  private func sendError(id: String, error: String) async {
    await sendJSON(["id": id, "type": "error", "error": error])
  }

  private func sendJSON(_ object: [String: Any]) async {
    do {
      let data = try JSONSerialization.data(withJSONObject: object)
      guard let text = String(data: data, encoding: .utf8) else { return }
      try await webSocketTask?.send(.string(text))
    } catch {
      Logger.error(.websocket, "Failed to send message: \(error)")
    }
  }
}

// MARK: - Capability Error

enum CapabilityError: LocalizedError {
  case unavailable

  var errorDescription: String? {
    "Capability is not available"
  }
}
