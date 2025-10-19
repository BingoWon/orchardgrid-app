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

  /// Default configuration
  static let `default` = APIServerConfiguration(
    port: 8888,
    defaultSystemPrompt: "You are a helpful AI assistant. Provide clear, concise, and accurate responses.",
    maxRequestSize: 65536
  )
}

/// Application configuration
struct AppConfiguration {
  /// API Server configuration
  let apiServer: APIServerConfiguration

  /// Default configuration
  static let `default` = AppConfiguration(
    apiServer: .default
  )
}
