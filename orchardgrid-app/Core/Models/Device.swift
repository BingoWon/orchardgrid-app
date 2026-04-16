import Foundation

struct Device: Codable, Identifiable, Sendable {
  let id: String
  let userId: String
  let platform: String
  let osVersion: String?
  let deviceName: String?
  let chipModel: String?
  let memoryGb: Double?
  let ipAddress: String?
  let countryCode: String?
  let isOnline: Bool
  let lastHeartbeat: Int?
  let logsProcessed: Int
  let failureCount: Int
  let createdAt: Int
  let updatedAt: Int

  enum CodingKeys: String, CodingKey {
    case id
    case userId = "user_id"
    case platform
    case osVersion = "os_version"
    case deviceName = "device_name"
    case chipModel = "chip_model"
    case memoryGb = "memory_gb"
    case ipAddress = "ip_address"
    case countryCode = "country_code"
    case isOnline = "is_online"
    case lastHeartbeat = "last_heartbeat"
    case logsProcessed = "logs_processed"
    case failureCount = "failure_count"
    case createdAt = "created_at"
    case updatedAt = "updated_at"
  }

  var flagEmoji: String {
    guard let code = countryCode, code.count == 2 else { return "" }
    return code.uppercased().unicodeScalars
      .map { String(UnicodeScalar(127_397 + $0.value)!) }
      .joined()
  }

  var platformIcon: String {
    switch platform.lowercased() {
    case "macos": "desktopcomputer"
    case "ios": "iphone"
    case "ipados": "ipad"
    default: "questionmark.circle"
    }
  }

  var statusText: String {
    isOnline ? String(localized: "Online") : String(localized: "Offline")
  }

  private static let lastSeenFormatter: RelativeDateTimeFormatter = {
    let f = RelativeDateTimeFormatter()
    f.unitsStyle = .full
    return f
  }()

  var lastSeenText: String {
    guard let heartbeat = lastHeartbeat else { return String(localized: "Never") }
    let date = Date(timeIntervalSince1970: TimeInterval(heartbeat) / 1000)
    return Self.lastSeenFormatter.localizedString(for: date, relativeTo: Date())
  }

  var shortOSVersion: String? {
    guard let v = osVersion else { return nil }
    guard let match = v.firstMatch(of: /Version\s+([\d.]+)/) else { return v }
    return String(match.1)
  }

  /// Chip model with "Apple " prefix stripped for display
  var displayChipModel: String? {
    guard let chip = chipModel else { return nil }
    return chip.hasPrefix("Apple ") ? String(chip.dropFirst(6)) : chip
  }
}
