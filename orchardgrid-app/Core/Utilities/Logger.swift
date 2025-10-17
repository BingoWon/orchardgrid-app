/**
 * Logger.swift
 * OrchardGrid Logging Utility
 *
 * Unified logging system for Console.app
 */

import OSLog

enum Logger {
  private static let subsystem = "com.orchardgrid.app"

  enum Category: String {
    case auth
    case websocket
    case api
    case apiServer
    case devices
    case app

    var logger: os.Logger {
      os.Logger(subsystem: Logger.subsystem, category: rawValue)
    }
  }

  static func log(_ category: Category, _ message: String) {
    category.logger.info("\(message, privacy: .public)")
  }

  static func error(_ category: Category, _ message: String) {
    category.logger.error("ERROR: \(message, privacy: .public)")
  }

  static func success(_ category: Category, _ message: String) {
    category.logger.notice("SUCCESS: \(message, privacy: .public)")
  }
}
