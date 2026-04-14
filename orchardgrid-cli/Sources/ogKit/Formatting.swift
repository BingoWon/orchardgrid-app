import Foundation

// MARK: - Column formatting

/// Right-pad `s` to at least `width` characters. Used by table-style output
/// in `og keys list`, `og devices`, `og logs`.
public func pad(_ s: String, _ width: Int) -> String {
  s.count >= width ? s : s + String(repeating: " ", count: width - s.count)
}

/// Format a JavaScript-style millisecond timestamp as `yyyy-MM-dd HH:mm:ss`
/// in the local timezone.
public func formatTimestamp(_ ms: Int64) -> String {
  let date = Date(timeIntervalSince1970: Double(ms) / 1000)
  let formatter = DateFormatter()
  formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
  return formatter.string(from: date)
}
