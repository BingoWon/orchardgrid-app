import Foundation

/// Protocol for managers that track last updated time
@MainActor
protocol Refreshable {
  var lastUpdated: Date? { get }
}

extension Refreshable {
  /// Formatted last updated time
  var lastUpdatedText: String {
    guard let lastUpdated else { return "Never" }
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .abbreviated
    return formatter.localizedString(for: lastUpdated, relativeTo: Date())
  }
}
