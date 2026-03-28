import Foundation
import Observation

@MainActor
@Observable
final class LogsManager: Refreshable {
  private(set) var logs: [LogEntry] = []
  private(set) var total = 0
  private(set) var isInitialLoading = true
  private(set) var isRefreshing = false
  private(set) var lastError: String?
  private(set) var lastUpdated: Date?

  private let apiURL = Config.apiBaseURL
  private let urlSession = Config.urlSession

  func reload(authToken: String, isManualRefresh: Bool = false) async {
    await loadLogs(authToken: authToken, isManualRefresh: isManualRefresh)
  }

  func loadLogs(
    limit: Int = 50,
    offset: Int = 0,
    status: String? = nil,
    role: String? = nil,
    authToken: String,
    isManualRefresh: Bool = false
  ) async {
    if logs.isEmpty {
      isInitialLoading = true
    } else if isManualRefresh {
      isRefreshing = true
    }
    lastError = nil

    do {
      var components = URLComponents(string: "\(apiURL)/logs")!
      components.queryItems = [
        URLQueryItem(name: "limit", value: "\(limit)"),
        URLQueryItem(name: "offset", value: "\(offset)"),
      ]
      if let status, status != "all" {
        components.queryItems?.append(URLQueryItem(name: "status", value: status))
      }
      if let role, role != "all" {
        components.queryItems?.append(URLQueryItem(name: "role", value: role))
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
        let errorMessage: String =
          if let errorData = try? JSONDecoder().decode(
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

      let result = try JSONDecoder().decode(LogsResponse.self, from: data)
      logs = result.logs
      total = result.total
      lastUpdated = Date()
    } catch is CancellationError {
      return
    } catch let error as URLError where error.code == .cancelled {
      return
    } catch {
      lastError = error.localizedDescription
      Logger.error(.app, "Load logs error: \(error)")
    }

    isInitialLoading = false
    isRefreshing = false
  }
}
