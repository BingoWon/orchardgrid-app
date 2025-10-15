import Foundation
import Observation

@MainActor
@Observable
final class LogsManager: AutoRefreshable {
  private(set) var consumingTasks: [ComputeTask] = []
  private(set) var providingTasks: [ComputeTask] = []
  private(set) var consumingTotal = 0
  private(set) var providingTotal = 0
  private(set) var isInitialLoading = true
  private(set) var isRefreshing = false
  private(set) var errorMessage: String?
  private(set) var lastUpdated: Date?

  var autoRefreshTask: Task<Void, Never>?

  // Save current filter and pagination state for auto-refresh
  private var currentConsumingParams: (limit: Int, offset: Int, status: String?) = (50, 0, nil)
  private var currentProvidingParams: (limit: Int, offset: Int, status: String?) = (50, 0, nil)

  private let apiURL = Config.apiBaseURL
  private let urlSession = Config.urlSession

  func loadConsumingTasks(
    limit: Int = 50,
    offset: Int = 0,
    status: String? = nil,
    authToken: String,
    isManualRefresh: Bool = false
  ) async {
    // Save current parameters for auto-refresh
    currentConsumingParams = (limit, offset, status)

    await loadTasks(
      endpoint: "/tasks",
      limit: limit,
      offset: offset,
      status: status,
      authToken: authToken,
      isManualRefresh: isManualRefresh
    ) { result in
      consumingTasks = result.tasks
      consumingTotal = result.total
    }
  }

  func loadProvidingTasks(
    limit: Int = 50,
    offset: Int = 0,
    status: String? = nil,
    authToken: String,
    isManualRefresh: Bool = false
  ) async {
    // Save current parameters for auto-refresh
    currentProvidingParams = (limit, offset, status)

    await loadTasks(
      endpoint: "/tasks/providing",
      limit: limit,
      offset: offset,
      status: status,
      authToken: authToken,
      isManualRefresh: isManualRefresh
    ) { result in
      providingTasks = result.tasks
      providingTotal = result.total
    }
  }

  private func loadTasks(
    endpoint: String,
    limit: Int,
    offset: Int,
    status: String?,
    authToken: String,
    isManualRefresh: Bool,
    onSuccess: (TasksResponse) -> Void
  ) async {
    // Only show loading indicator for initial load
    if consumingTasks.isEmpty, providingTasks.isEmpty {
      isInitialLoading = true
    } else if isManualRefresh {
      isRefreshing = true
    }
    errorMessage = nil

    do {
      var components = URLComponents(string: "\(apiURL)\(endpoint)")!
      components.queryItems = [
        URLQueryItem(name: "limit", value: "\(limit)"),
        URLQueryItem(name: "offset", value: "\(offset)"),
      ]
      if let status, status != "all" {
        components.queryItems?.append(URLQueryItem(name: "status", value: status))
      }

      var request = URLRequest(url: components.url!)
      request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")

      let (data, response) = try await urlSession.data(for: request)

      guard let httpResponse = response as? HTTPURLResponse,
            httpResponse.statusCode == 200
      else {
        throw NSError(
          domain: "LogsManager",
          code: -1,
          userInfo: [NSLocalizedDescriptionKey: "Failed to load tasks"]
        )
      }

      let result = try JSONDecoder().decode(TasksResponse.self, from: data)
      onSuccess(result)
      lastUpdated = Date()
    } catch {
      errorMessage = error.localizedDescription
      Logger.log(.app, "Load tasks error: \(error)")
    }

    isInitialLoading = false
    isRefreshing = false
  }

  // MARK: - Auto Refresh

  func startAutoRefresh(interval: TimeInterval, authToken: String) async {
    stopAutoRefresh()

    autoRefreshTask = Task { @MainActor in
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(interval))
        guard !Task.isCancelled else { break }
        // Refresh both consuming and providing tasks with saved parameters
        await loadConsumingTasks(
          limit: currentConsumingParams.limit,
          offset: currentConsumingParams.offset,
          status: currentConsumingParams.status,
          authToken: authToken
        )
        await loadProvidingTasks(
          limit: currentProvidingParams.limit,
          offset: currentProvidingParams.offset,
          status: currentProvidingParams.status,
          authToken: authToken
        )
      }
    }
  }

  func stopAutoRefresh() {
    autoRefreshTask?.cancel()
    autoRefreshTask = nil
  }
}
