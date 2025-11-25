import Foundation

// MARK: - Device Model

struct Device: Codable, Identifiable {
  let id: String
  let userId: String
  var platform: String
  var osVersion: String?
  var deviceName: String?
  var chipModel: String?
  var memoryGb: Double?
  var isOnline: Bool
  var lastHeartbeat: Int?
  var tasksProcessed: Int
  var failureCount: Int
  let createdAt: Int
  var updatedAt: Int

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
final class DevicesManager: AutoRefreshable {
  private(set) var devices: [Device] = []
  private(set) var isInitialLoading = true
  private(set) var isRefreshing = false
  private(set) var lastError: String?
  private(set) var lastUpdated: Date?

  var autoRefreshTask: Task<Void, Never>?

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

  // MARK: - Monitoring

  private var monitorWebSocket: URLSessionWebSocketTask?
  private var monitorURLSession: URLSession?
  private var currentAuthToken: String?
  private var currentUserId: String?

  func startMonitoring(authToken: String, userId: String) async {
    self.currentAuthToken = authToken
    self.currentUserId = userId
    
    // Initial fetch to get full history including offline devices
    await fetchDevices(authToken: authToken)
    
    // Connect to WebSocket for real-time updates
    connectMonitor()
  }
  
  func stopMonitoring() {
    monitorWebSocket?.cancel(with: .goingAway, reason: nil)
    monitorWebSocket = nil
    monitorURLSession?.invalidateAndCancel()
    monitorURLSession = nil
  }

  private func connectMonitor() {
    guard let userId = currentUserId else { return }
    
    stopMonitoring()
    
    let wsURLString = apiURL
        .replacingOccurrences(of: "https://", with: "wss://")
        .replacingOccurrences(of: "http://", with: "ws://")
        + "/monitor?user_id=\(userId)"
        
    guard let url = URL(string: wsURLString) else { return }
    
    let session = URLSession(configuration: .default)
    monitorURLSession = session
    let task = session.webSocketTask(with: url)
    monitorWebSocket = task
    task.resume()
    
    Logger.log(.devices, "Monitor connecting to: \(url)")
    
    receiveMonitorMessage()
  }

  private func receiveMonitorMessage() {
    monitorWebSocket?.receive { [weak self] result in
      guard let self else { return }
      
      switch result {
      case .success(let message):
        switch message {
        case .string(let text):
            self.handleMonitorPayload(text)
        case .data(let data):
            if let text = String(data: data, encoding: .utf8) {
                self.handleMonitorPayload(text)
            }
        @unknown default: break
        }
        self.receiveMonitorMessage()
        
      case .failure(let error):
        Logger.error(.devices, "Monitor WS error: \(error)")
        // Simple reconnect logic
        Task {
            try? await Task.sleep(for: .seconds(3))
            await MainActor.run { self.connectMonitor() }
        }
      }
    }
  }

  private func handleMonitorPayload(_ text: String) {
    guard let data = text.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let type = json["type"] as? String else { return }
          
    let payload = json["payload"] as? [String: Any]
    
    Task { @MainActor in
        switch type {
        case "INITIAL_STATE":
            if let devicesArray = payload?["devices"] as? [[String: Any]],
               let devicesData = try? JSONSerialization.data(withJSONObject: devicesArray),
               let devices = try? JSONDecoder().decode([Device].self, from: devicesData) {
                   
                   for device in devices {
                       if let index = self.devices.firstIndex(where: { $0.id == device.id }) {
                           self.devices[index] = device
                       } else {
                           self.devices.insert(device, at: 0)
                       }
                   }
                   self.lastUpdated = Date()
            }
            
        case "DEVICE_CONNECTED":
             if let payload = payload,
                let deviceData = try? JSONSerialization.data(withJSONObject: payload),
                let device = try? JSONDecoder().decode(Device.self, from: deviceData) {
                 
                    var newDevice = device
                    newDevice.isOnline = true
                    
                    if let index = self.devices.firstIndex(where: { $0.id == device.id }) {
                        self.devices[index] = newDevice
                    } else {
                        self.devices.insert(newDevice, at: 0)
                    }
                    self.lastUpdated = Date()
             }

        case "DEVICE_UPDATED":
            if let id = payload?["id"] as? String,
               let index = self.devices.firstIndex(where: { $0.id == id }) {
                
                if let count = payload?["tasksProcessed"] as? Int {
                    self.devices[index].tasksProcessed = count
                }
                
                if let failures = payload?["failureCount"] as? Int {
                    self.devices[index].failureCount = failures
                }
                
                self.lastUpdated = Date()
            }

        case "DEVICE_DISCONNECTED":
            if let id = payload?["id"] as? String,
               let index = self.devices.firstIndex(where: { $0.id == id }) {
                self.devices[index].isOnline = false
                self.lastUpdated = Date()
            }
            
        default: break
        }
    }
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
