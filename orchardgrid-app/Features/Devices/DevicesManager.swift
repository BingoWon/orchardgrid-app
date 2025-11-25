import Foundation

// MARK: - Device Model

struct Device: Codable, Identifiable {
  let id: String
  let userId: String
  let platform: String
  let osVersion: String?
  let deviceName: String?
  let chipModel: String?
  let memoryGb: Double?
  let isOnline: Bool
  let lastHeartbeat: Int?
  let tasksProcessed: Int
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
    case isOnline = "is_online"
    case lastHeartbeat = "last_heartbeat"
    case tasksProcessed = "tasks_processed"
    case failureCount = "failure_count"
    case createdAt = "created_at"
    case updatedAt = "updated_at"
  }

  var isActuallyOnline: Bool {
    // Check is_online first (immediate update on disconnect)
    guard isOnline else { return false }
    // Then verify heartbeat (fallback for stale connections)
    guard let heartbeat = lastHeartbeat else { return false }
    let now = Int(Date().timeIntervalSince1970 * 1000)
    return now - heartbeat < DeviceConfig.staleThreshold
  }

  var platformIcon: String {
    switch platform.lowercased() {
    case "macos": "desktopcomputer"
    case "ios": "iphone"
    case "ipados": "ipad"
    default: "questionmark.circle"
    }
  }

  var statusColor: String {
    isActuallyOnline ? "green" : "gray"
  }

  var statusText: String {
    isActuallyOnline ? "Online" : "Offline"
  }

  var lastSeenText: String {
    guard let heartbeat = lastHeartbeat else { return "Never" }
    // Backend returns milliseconds, convert to seconds
    let date = Date(timeIntervalSince1970: TimeInterval(heartbeat) / 1000)
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .full
    return formatter.localizedString(for: date, relativeTo: Date())
  }

  var shortOSVersion: String? {
    guard let v = osVersion else { return nil }
    let pattern = #"Version\s+([\d.]+)"#
    guard let regex = try? NSRegularExpression(pattern: pattern),
          let match = regex.firstMatch(in: v, range: NSRange(v.startIndex..., in: v)),
          let range = Range(match.range(at: 1), in: v)
    else { return v }
    return String(v[range])
  }
}

// MARK: - Devices Manager

@MainActor
@Observable
final class DevicesManager: Refreshable {
  private(set) var devices: [Device] = []
  private(set) var isInitialLoading = true
  private(set) var isRefreshing = false
  private(set) var lastError: String?
  private(set) var lastUpdated: Date?

  private let apiURL = Config.apiBaseURL

  func fetchDevices(authToken: String, isManualRefresh: Bool = false) async {
    // Only show loading indicator for initial load
    if devices.isEmpty {
      isInitialLoading = true
    } else if isManualRefresh {
      isRefreshing = true
    }
    lastError = nil

    do {
      let url = URL(string: "\(apiURL)/devices")!
      var request = URLRequest(url: url)
      request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")

      Logger.log(.devices, "Fetching from: \(url.absoluteString)")
      Logger.log(.devices, "Token: \(String(authToken.prefix(20)))...")

      let (data, response) = try await Config.urlSession.data(for: request)

      guard let httpResponse = response as? HTTPURLResponse else {
        throw URLError(.badServerResponse)
      }

      if httpResponse.statusCode == 401 {
        Logger.error(.devices, "Unauthorized (401)")
        if let responseString = String(data: data, encoding: .utf8) {
          Logger.error(.devices, "Response: \(responseString)")
        }
        throw NSError(
          domain: "DevicesManager",
          code: 401,
          userInfo: [NSLocalizedDescriptionKey: "Unauthorized"]
        )
      }

      if httpResponse.statusCode != 200 {
        Logger.error(.devices, "HTTP \(httpResponse.statusCode)")
        if let responseString = String(data: data, encoding: .utf8) {
          Logger.error(.devices, "Response: \(responseString)")
        }
        throw NSError(
          domain: "DevicesManager",
          code: httpResponse.statusCode,
          userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode)"]
        )
      }

      let decoder = JSONDecoder()
      devices = try decoder.decode([Device].self, from: data)
      lastError = nil
      lastUpdated = Date()

      Logger.success(.devices, "Fetched \(devices.count) devices")
    } catch {
      Logger.error(.devices, "Failed to fetch devices: \(error)")
      lastError = error.localizedDescription
      devices = []
    }

    isInitialLoading = false
    isRefreshing = false
  }

  var onlineDevices: [Device] {
    devices.filter(\.isOnline)
  }

  var offlineDevices: [Device] {
    devices.filter { !$0.isOnline }
  }

  var totalTasksProcessed: Int {
    devices.reduce(0) { $0 + $1.tasksProcessed }
  }
}
