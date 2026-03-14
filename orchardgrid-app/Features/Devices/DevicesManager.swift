import Foundation

@MainActor
@Observable
final class DevicesManager: Refreshable {
  private(set) var devices: [Device] = []
  private(set) var isInitialLoading = true
  private(set) var isRefreshing = false
  private(set) var lastError: String?
  private(set) var lastUpdated: Date?

  func fetchDevices(authToken: String, isManualRefresh: Bool = false) async {
    if devices.isEmpty {
      isInitialLoading = true
    } else if isManualRefresh {
      isRefreshing = true
    }
    lastError = nil

    do {
      let url = URL(string: "\(Config.apiBaseURL)/devices")!
      var request = URLRequest(url: url)
      request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")

      let (data, response) = try await Config.urlSession.data(for: request)

      guard let httpResponse = response as? HTTPURLResponse else {
        throw URLError(.badServerResponse)
      }

      guard httpResponse.statusCode == 200 else {
        if let body = String(data: data, encoding: .utf8) {
          Logger.error(.devices, "HTTP \(httpResponse.statusCode): \(body)")
        }
        throw NSError(
          domain: "DevicesManager",
          code: httpResponse.statusCode,
          userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode)"]
        )
      }

      devices = try JSONDecoder().decode([Device].self, from: data)
      lastError = nil
      lastUpdated = Date()
      Logger.success(.devices, "Fetched \(devices.count) devices")
    } catch is CancellationError {
      return
    } catch let error as URLError where error.code == .cancelled {
      return
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
