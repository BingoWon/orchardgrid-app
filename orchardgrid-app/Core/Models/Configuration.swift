/**
 * Configuration.swift
 * OrchardGrid Configuration Management
 *
 * Centralized configuration for the application
 */

import Foundation

/// API Server configuration
struct APIServerConfiguration {
  /// Server port
  let port: UInt16

  /// Default system prompt for LLM
  let defaultSystemPrompt: String

  /// Maximum request size in bytes
  let maxRequestSize: Int

  /// Request timeout in seconds
  let timeout: TimeInterval

  /// Default configuration
  static let `default` = APIServerConfiguration(
    port: 8888,
    defaultSystemPrompt: "You are a helpful AI assistant. Provide clear, concise, and accurate responses.",
    maxRequestSize: 65536,
    timeout: 30
  )
}

/// WebSocket client configuration
struct WebSocketClientConfiguration {
  /// Server URL
  let serverURL: String

  /// Default system prompt for LLM
  let defaultSystemPrompt: String

  /// Heartbeat interval in seconds
  let heartbeatInterval: TimeInterval

  /// Heartbeat timeout in seconds
  let heartbeatTimeout: TimeInterval

  /// Maximum reconnection attempts
  let maxReconnectAttempts: Int

  /// Initial reconnection delay in seconds
  let initialReconnectDelay: TimeInterval

  /// Maximum reconnection delay in seconds
  let maxReconnectDelay: TimeInterval

  /// Default configuration
  static let `default` = WebSocketClientConfiguration(
    serverURL: "wss://orchardgrid.com/ws",
    defaultSystemPrompt: "You are a helpful AI assistant. Provide clear, concise, and accurate responses.",
    heartbeatInterval: 30,
    heartbeatTimeout: 10,
    maxReconnectAttempts: 10,
    initialReconnectDelay: 1,
    maxReconnectDelay: 60
  )
}

/// Application configuration
struct AppConfiguration {
  /// API Server configuration
  let apiServer: APIServerConfiguration

  /// WebSocket client configuration
  let webSocketClient: WebSocketClientConfiguration

  /// Default configuration
  static let `default` = AppConfiguration(
    apiServer: .default,
    webSocketClient: .default
  )
}
