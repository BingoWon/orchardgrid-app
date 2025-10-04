/**
 * NetworkManager.swift
 * OrchardGrid Network Manager
 *
 * Shared URLSession configuration for all network requests
 */

import Foundation

enum NetworkManager {
  /// Shared URLSession with optimized timeout configuration
  static let shared: URLSession = {
    let configuration = URLSessionConfiguration.default
    configuration.timeoutIntervalForRequest = 10 // 10 seconds per request
    configuration.timeoutIntervalForResource = 30 // 30 seconds for entire resource
    return URLSession(configuration: configuration)
  }()
}
