/**
 * DeviceConfig.swift
 * OrchardGrid Device Configuration
 *
 * Centralized configuration for device and WebSocket client
 */

import Foundation

enum DeviceConfig {
  // Heartbeat settings (must match backend CONFIG)
  static let heartbeatInterval: TimeInterval = 15 // 15 seconds
  static let heartbeatTimeout: TimeInterval = 45 // 45 seconds (3x interval)
  static let staleThreshold: Int = 45000 // 45 seconds in milliseconds

  // LLM settings
  static let defaultSystemPrompt = "You are a helpful AI assistant. Provide clear, concise, and accurate responses."
}
