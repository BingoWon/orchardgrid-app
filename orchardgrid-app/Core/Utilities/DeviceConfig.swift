/**
 * DeviceConfig.swift
 * OrchardGrid Device Configuration
 *
 * Centralized configuration for device and WebSocket client
 */

import Foundation

enum DeviceConfig {
  // Heartbeat settings (must match backend CONFIG)
  static let heartbeatInterval: TimeInterval = 15
  static let heartbeatTimeout: TimeInterval = 45
  static let staleThreshold: Int = 45000

  // Connection timeouts
  static let connectionRequestTimeout: TimeInterval = 60
  static let connectionTimeout: TimeInterval = 30
  static let reconnectionCheckInterval: TimeInterval = 5
}
