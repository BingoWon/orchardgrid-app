import Foundation
import Observation

@MainActor
@Observable
final class LogsManager: Refreshable {
  private(set) var consumingTasks: [ComputeTask] = []
  private(set) var providingTasks: [ComputeTask] = []
  private(set) var consumingTotal = 0
  private(set) var providingTotal = 0
  private(set) var isInitialLoading = true
  private(set) var isRefreshing = false
  private(set) var errorMessage: String?
  private(set) var lastUpdated: Date?

  private let apiURL = Config.apiBaseURL
  private let urlSession = Config.urlSession

  /// Quick reload for real-time updates (uses default pagination)
  func reload(authToken: String, isManualRefresh: Bool = false) async {
    await loadConsumingTasks(authToken: authToken, isManualRefresh: isManualRefresh)
    await loadProvidingTasks(authToken: authToken, isManualRefresh: isManualRefresh)
  }

  func loadConsumingTasks(
    limit: Int = 50,
    offset: Int = 0,
    status: String? = nil,
    authToken: String,
    isManualRefresh: Bool = false
  ) async {
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

      guard let httpResponse = response as? HTTPURLResponse else {
        throw NSError(
          domain: "LogsManager",
          code: -1,
          userInfo: [NSLocalizedDescriptionKey: "Invalid server response"]
        )
      }

      guard httpResponse.statusCode == 200 else {
        // Try to parse error message from response
        let errorMessage: String = if let errorData = try? JSONDecoder().decode(
          [String: String].self,
          from: data
        ),
          let message = errorData["error"]
        {
          message
        } else {
          "Server returned status code \(httpResponse.statusCode)"
        }

        throw NSError(
          domain: "LogsManager",
          code: httpResponse.statusCode,
          userInfo: [NSLocalizedDescriptionKey: errorMessage]
        )
      }

      let result = try JSONDecoder().decode(TasksResponse.self, from: data)
      onSuccess(result)
      lastUpdated = Date()
    } catch {
      errorMessage = error.localizedDescription
      Logger.error(.app, "Load tasks error: \(error)")
    }

    isInitialLoading = false
    isRefreshing = false
  }
}
