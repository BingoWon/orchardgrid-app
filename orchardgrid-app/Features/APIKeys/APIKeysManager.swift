import Foundation

@MainActor
@Observable
final class APIKeysManager: Refreshable {
  private(set) var apiKeys: [APIKey] = []
  private(set) var isInitialLoading = true
  private(set) var isRefreshing = false
  private(set) var lastError: APIError?
  private(set) var lastUpdated: Date?

  private let api: APIClient

  init(api: APIClient) {
    self.api = api
  }

  func loadAPIKeys(isManualRefresh: Bool = false) async {
    if apiKeys.isEmpty {
      isInitialLoading = true
    } else if isManualRefresh {
      isRefreshing = true
    }
    lastError = nil

    do {
      let response: ListResponse = try await api.get("/api-keys")
      apiKeys = response.keys
      lastUpdated = Date()
    } catch is CancellationError {
      return
    } catch {
      let apiError = APIError.classify(error)
      if case .transport(let urlError) = apiError, urlError.code == .cancelled { return }
      lastError = apiError
      Logger.error(.api, "Failed to load API keys: \(apiError)")
    }

    isInitialLoading = false
    isRefreshing = false
  }

  @discardableResult
  func createAPIKey(name: String) async -> APIKey? {
    do {
      let key: APIKey = try await api.post("/api-keys", body: ["name": name])
      await loadAPIKeys()
      return key
    } catch {
      lastError = APIError.classify(error)
      Logger.error(.api, "Failed to create API key: \(error)")
      return nil
    }
  }

  func updateAPIKey(hint: String, name: String) async {
    do {
      try await api.patch(path(for: hint), body: ["name": name])
      await loadAPIKeys()
    } catch {
      lastError = APIError.classify(error)
      Logger.error(.api, "Failed to update API key: \(error)")
    }
  }

  func deleteAPIKey(hint: String) async {
    do {
      try await api.delete(path(for: hint))
      await loadAPIKeys()
    } catch {
      lastError = APIError.classify(error)
      Logger.error(.api, "Failed to delete API key: \(error)")
    }
  }

  private func path(for hint: String) -> String {
    let encoded = hint.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? hint
    return "/api-keys/\(encoded)"
  }

  private struct ListResponse: Decodable {
    let keys: [APIKey]
  }
}
