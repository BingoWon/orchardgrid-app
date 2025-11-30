/**
 * Config.swift
 * OrchardGrid Configuration
 */

import Foundation

enum Config {
  static var apiBaseURL: String {
    ProcessInfo.processInfo.environment["API_BASE_URL"]
      ?? Bundle.main.infoDictionary?["API_BASE_URL"] as? String
      ?? "https://api.orchardgrid.com"
  }

  static var webSocketBaseURL: String {
    apiBaseURL
      .replacingOccurrences(of: "https://", with: "wss://")
      .replacingOccurrences(of: "http://", with: "ws://")
  }

  // Google Sign-In Client IDs
  // Note: Client ID is primarily loaded from Info.plist via GIDSignIn SDK
  // This property is kept for reference or legacy compatibility if needed
  static var googleClientID: String {
    "600208131492-kn9b46tihg0l85nda6gfstle98du99c7.apps.googleusercontent.com"
  }

  static let urlSession: URLSession = {
    let config = URLSessionConfiguration.default
    config.timeoutIntervalForRequest = 10
    config.timeoutIntervalForResource = 30
    return URLSession(configuration: config)
  }()
}
