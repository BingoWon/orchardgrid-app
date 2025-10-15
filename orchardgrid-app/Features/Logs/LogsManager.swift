import Foundation
import Observation

@MainActor
@Observable
final class LogsManager: AutoRefreshable {
  var consumingTasks: [ComputeTask] = []
  var providingTasks: [ComputeTask] = []
  var consumingTotal = 0
  var providingTotal = 0
  var isLoading = false
  var errorMessage: String?
  var lastUpdated: Date?

  var autoRefreshTask: Task<Void, Never>?

  private let apiURL = Config.apiBaseURL
  private let urlSession = Config.urlSession

  func loadConsumingTasks(
    limit: Int = 50,
    offset: Int = 0,
    status: String? = nil,
    authToken: String
  ) async {
    await loadTasks(
      endpoint: "/tasks",
      limit: limit,
      offset: offset,
      status: status,
      authToken: authToken
    ) { result in
      consumingTasks = result.tasks
      consumingTotal = result.total
    }
  }

  func loadProvidingTasks(
    limit: Int = 50,
    offset: Int = 0,
    status: String? = nil,
    authToken: String
  ) async {
    await loadTasks(
      endpoint: "/tasks/providing",
      limit: limit,
      offset: offset,
      status: status,
      authToken: authToken
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
    onSuccess: (TasksResponse) -> Void
  ) async {
    isLoading = true
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

    isLoading = false
  }

  // MARK: - Auto Refresh

  func startAutoRefresh(interval: TimeInterval, authToken: String) async {
    stopAutoRefresh()

    autoRefreshTask = Task { @MainActor in
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(interval))
        guard !Task.isCancelled else { break }
        // Refresh both consuming and providing tasks
        await loadConsumingTasks(authToken: authToken)
        await loadProvidingTasks(authToken: authToken)
      }
    }
  }

  func stopAutoRefresh() {
    autoRefreshTask?.cancel()
    autoRefreshTask = nil
  }
}
