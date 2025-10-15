import Foundation
import SwiftUI

/// Global refresh configuration for all data managers
enum RefreshConfig {
  /// Auto-refresh interval in seconds (default: disabled)
  static let defaultInterval: TimeInterval = 10.0
  
  /// Available refresh intervals
  static let availableIntervals: [TimeInterval] = [5.0, 10.0, 30.0, 60.0]
  
  /// Interval display names
  static func intervalName(for interval: TimeInterval) -> String {
    switch interval {
    case 5.0: "5 seconds"
    case 10.0: "10 seconds"
    case 30.0: "30 seconds"
    case 60.0: "1 minute"
    default: "\(Int(interval)) seconds"
    }
  }
}

/// Protocol for managers that support auto-refresh
@MainActor
protocol AutoRefreshable {
  var lastUpdated: Date? { get }
  var autoRefreshTask: Task<Void, Never>? { get set }
  
  func startAutoRefresh(interval: TimeInterval, authToken: String) async
  func stopAutoRefresh()
}

extension AutoRefreshable {
  /// Formatted last updated time
  var lastUpdatedText: String {
    guard let lastUpdated else { return "Never" }
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .abbreviated
    return formatter.localizedString(for: lastUpdated, relativeTo: Date())
  }
}

