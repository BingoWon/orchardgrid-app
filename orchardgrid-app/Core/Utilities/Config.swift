/**
 * Config.swift
 * OrchardGrid Configuration
 *
 * Environment-specific configuration using .xcconfig files
 */

import Foundation

enum Config {
  /// API Base URL
  /// Priority: Environment Variable > Info.plist > Compile-time Default
  static var apiBaseURL: String {
    // 1. Environment variable (for testing/CI)
    if let envURL = ProcessInfo.processInfo.environment["API_BASE_URL"] {
      return envURL
    }

    // 2. Info.plist (from .xcconfig)
    if let plistURL = Bundle.main.infoDictionary?["API_BASE_URL"] as? String {
      return plistURL
    }

    // 3. Compile-time default
    #if DEBUG
      return "https://orchardgrid-api-development.bingow.workers.dev"
    #else
      return "https://orchardgrid-api.bingow.workers.dev"
    #endif
  }

  /// Google OAuth Client ID
  static var googleClientID: String {
    if let envID = ProcessInfo.processInfo.environment["GOOGLE_CLIENT_ID"] {
      return envID
    }

    if let plistID = Bundle.main.infoDictionary?["GOOGLE_CLIENT_ID"] as? String {
      return plistID
    }

    return "YOUR_GOOGLE_CLIENT_ID.apps.googleusercontent.com"
  }

  /// Current environment
  static var environment: Environment {
    #if DEBUG
      .development
    #else
      .production
    #endif
  }

  enum Environment: String {
    case development
    case production

    var displayName: String {
      switch self {
      case .development: "Development"
      case .production: "Production"
      }
    }
  }

  /// Shared URLSession with optimized timeout configuration
  static let urlSession: URLSession = {
    let configuration = URLSessionConfiguration.default
    configuration.timeoutIntervalForRequest = 10 // 10 seconds per request
    configuration.timeoutIntervalForResource = 30 // 30 seconds for entire resource
    return URLSession(configuration: configuration)
  }()
}
