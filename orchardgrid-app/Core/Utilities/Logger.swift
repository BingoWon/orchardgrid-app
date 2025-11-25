/**
 * Logger.swift
 * OrchardGrid Logging Utility
 */

import Foundation
import OSLog

enum Logger {
  private static let subsystem = "com.orchardgrid.app"

  enum Category: String {
    case auth
    case websocket
    case api
    case devices
    case app
    case observer

    var logger: os.Logger {
      os.Logger(subsystem: Logger.subsystem, category: rawValue)
    }

    var emoji: String {
      switch self {
      case .auth: "🔐"
      case .websocket: "🔌"
      case .api: "🌐"
      case .devices: "📱"
      case .app: "📦"
      case .observer: "👁️"
      }
    }
  }

  static func log(_ category: Category, _ message: String) {
    let output = "\(category.emoji) [\(category.rawValue.uppercased())] \(message)"
    category.logger.info("\(output, privacy: .public)")
  }

  static func error(_ category: Category, _ message: String) {
    let output = "❌ [\(category.rawValue.uppercased())] \(message)"
    category.logger.error("\(output, privacy: .public)")
  }

  static func success(_ category: Category, _ message: String) {
    let output = "✅ [\(category.rawValue.uppercased())] \(message)"
    category.logger.notice("\(output, privacy: .public)")
  }
}
