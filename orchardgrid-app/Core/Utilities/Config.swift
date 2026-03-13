import Foundation

enum Config {
  static var hostURL: String {
    ProcessInfo.processInfo.environment["API_BASE_URL"]
      ?? Bundle.main.infoDictionary?["API_BASE_URL"] as? String
      ?? "https://orchardgrid.com"
  }

  static var apiBaseURL: String {
    "\(hostURL)/api"
  }

  static var webSocketBaseURL: String {
    hostURL
      .replacingOccurrences(of: "https://", with: "wss://")
      .replacingOccurrences(of: "http://", with: "ws://")
      + "/ws"
  }

  static var clerkPublishableKey: String {
    Bundle.main.infoDictionary?["CLERK_PUBLISHABLE_KEY"] as? String
      ?? "pk_test_cmF0aW9uYWwtamFndWFyLTQ5LmNsZXJrLmFjY291bnRzLmRldiQ"
  }

  static let urlSession: URLSession = {
    let config = URLSessionConfiguration.default
    config.timeoutIntervalForRequest = 10
    config.timeoutIntervalForResource = 30
    return URLSession(configuration: config)
  }()
}
