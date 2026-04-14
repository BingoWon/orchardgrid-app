import Foundation

@MainActor
@Observable
final class LogsManager: Refreshable {
  private(set) var logs: [LogEntry] = []
  private(set) var total = 0
  private(set) var isInitialLoading = true
  private(set) var isRefreshing = false
  private(set) var lastError: APIError?
  private(set) var lastUpdated: Date?

  private let api: APIClient

  init(api: APIClient) {
    self.api = api
  }

  func reload(isManualRefresh: Bool = false) async {
    await loadLogs(isManualRefresh: isManualRefresh)
  }

  func loadLogs(
    limit: Int = 50,
    offset: Int = 0,
    status: String? = nil,
    role: String? = nil,
    isManualRefresh: Bool = false
  ) async {
    if logs.isEmpty {
      isInitialLoading = true
    } else if isManualRefresh {
      isRefreshing = true
    }
    lastError = nil

    var query: [URLQueryItem] = [
      .init(name: "limit", value: String(limit)),
      .init(name: "offset", value: String(offset)),
    ]
    if let status, status != "all" { query.append(.init(name: "status", value: status)) }
    if let role, role != "all" { query.append(.init(name: "role", value: role)) }

    do {
      let result: LogsResponse = try await api.get("/logs", query: query)
      logs = result.logs
      total = result.total
      lastUpdated = Date()
    } catch is CancellationError {
      return
    } catch {
      let apiError = APIError.classify(error)
      if case .transport(let urlError) = apiError, urlError.code == .cancelled { return }
      lastError = apiError
      Logger.error(.app, "Load logs error: \(apiError)")
    }

    isInitialLoading = false
    isRefreshing = false
  }
}
