import Foundation

private let relativeFormatter: RelativeDateTimeFormatter = {
  let f = RelativeDateTimeFormatter()
  f.unitsStyle = .abbreviated
  return f
}()

@MainActor
protocol Refreshable {
  var lastUpdated: Date? { get }
  var lastError: APIError? { get }
}

extension Refreshable {
  var lastUpdatedText: String {
    guard let lastUpdated else { return "Never" }
    return relativeFormatter.localizedString(for: lastUpdated, relativeTo: Date())
  }
}
