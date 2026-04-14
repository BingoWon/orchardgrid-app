import Foundation

@MainActor
@Observable
final class DevicesManager: Refreshable {
  private(set) var devices: [Device] = []
  private(set) var isInitialLoading = true
  private(set) var isRefreshing = false
  private(set) var lastError: APIError?
  private(set) var lastUpdated: Date?

  private let api: APIClient

  init(api: APIClient) {
    self.api = api
  }

  func fetchDevices(isManualRefresh: Bool = false) async {
    if devices.isEmpty {
      isInitialLoading = true
    } else if isManualRefresh {
      isRefreshing = true
    }
    lastError = nil

    do {
      devices = try await api.get("/devices")
      lastUpdated = Date()
      Logger.success(.devices, "Fetched \(devices.count) devices")
    } catch is CancellationError {
      return
    } catch {
      let apiError = APIError.classify(error)
      if case .transport(let urlError) = apiError, urlError.code == .cancelled { return }
      lastError = apiError
      devices = []
      Logger.error(.devices, "Failed to fetch devices: \(apiError)")
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

  var totalLogsProcessed: Int {
    devices.reduce(0) { $0 + $1.logsProcessed }
  }
}
