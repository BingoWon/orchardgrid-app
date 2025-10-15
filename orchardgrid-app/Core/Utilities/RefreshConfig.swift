import Foundation
import SwiftUI

/// Global refresh configuration for all data managers
enum RefreshConfig {
  /// Auto-refresh interval in seconds (always enabled)
  static let interval: TimeInterval = 10.0
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
