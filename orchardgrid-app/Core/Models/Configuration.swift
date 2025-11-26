/**
 * Configuration.swift
 * OrchardGrid Configuration Management
 *
 * Centralized configuration for the application
 */

import Foundation

/// Shared LLM configuration
enum LLMConfig {
  /// Default system prompt for all LLM interactions
  static let defaultSystemPrompt =
    "You are a helpful AI assistant. Provide clear, concise, and accurate responses."
}

/// API Server configuration
struct APIServerConfiguration {
  /// Server port
  let port: UInt16

  /// Maximum request size in bytes
  let maxRequestSize: Int

  /// Default configuration
  static let `default` = APIServerConfiguration(
    port: 8888,
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
