/**
 * DeviceConfig.swift
 * OrchardGrid Device Configuration
 *
 * Centralized configuration for device heartbeat and status management
 */

import Foundation

enum DeviceConfig {
  // Heartbeat settings (must match backend CONFIG)
  static let heartbeatInterval: TimeInterval = 15 // 15 seconds
  static let heartbeatTimeout: TimeInterval = 45 // 45 seconds (3x interval)
  static let staleThreshold: Int = 45000 // 45 seconds in milliseconds

  // Auto-refresh settings
  static let deviceListRefreshInterval: TimeInterval = 5 // 5 seconds
}
