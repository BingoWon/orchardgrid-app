import Foundation

enum Config {
  // MARK: - API

  static let hostURL: String = {
    if let env = ProcessInfo.processInfo.environment["API_BASE_URL"] { return env }
    guard let plist = Bundle.main.infoDictionary?["API_BASE_URL"] as? String else {
      fatalError("API_BASE_URL not set in Info.plist or environment")
    }
    return plist
  }()

  static var apiBaseURL: String { "\(hostURL)/api" }

  static var webSocketBaseURL: String {
    hostURL
      .replacingOccurrences(of: "https://", with: "wss://")
      .replacingOccurrences(of: "http://", with: "ws://")
      + "/ws"
  }

  static let clerkPublishableKey: String = {
    guard let key = Bundle.main.infoDictionary?["CLERK_PUBLISHABLE_KEY"] as? String else {
      fatalError("CLERK_PUBLISHABLE_KEY not set in Info.plist")
    }
    return key
  }()

  static let urlSession: URLSession = {
    let config = URLSessionConfiguration.default
    config.timeoutIntervalForRequest = 10
    config.timeoutIntervalForResource = 30
    return URLSession(configuration: config)
  }()

  // MARK: - WebSocket / Device

  static let heartbeatInterval: TimeInterval = 15
  static let heartbeatTimeout: TimeInterval = 45
  static let connectionRequestTimeout: TimeInterval = 30
  static let connectionTimeout: TimeInterval = 15

  // MARK: - LLM

  static let defaultSystemPrompt =
    "You are a helpful AI assistant. Provide clear, concise, and accurate responses."

  /// Tokens reserved for the model's output when computing the input budget.
  static let llmOutputReserve = 512

  // MARK: - Local API Server

  static let apiServerPort: UInt16 = 8888
  static let maxRequestSize = 10_485_760
}
