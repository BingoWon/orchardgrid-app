/**
 * APIKeysManager.swift
 * OrchardGrid API Keys Manager
 */

import Foundation

struct APIKey: Identifiable, Codable, Sendable {
  let key: String
  let name: String?
  let created_at: Int
  let last_used_at: Int?

  var id: String { key }
}

@MainActor
@Observable
final class APIKeysManager: AutoRefreshable {
  var apiKeys: [APIKey] = []
  var isLoading = false
  var lastError: String?
  var lastUpdated: Date?

  var autoRefreshTask: Task<Void, Never>?

  private let apiURL = Config.apiBaseURL
  private let urlSession = Config.urlSession

  func loadAPIKeys(authToken: String) async {
    isLoading = true
    lastError = nil

    do {
      let url = URL(string: "\(apiURL)/api-keys")!
      var request = URLRequest(url: url)
      request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")

      Logger.log(.api, "Fetching API keys from: \(url.absoluteString)")

      let (data, response) = try await urlSession.data(for: request)

      guard let httpResponse = response as? HTTPURLResponse else {
        throw NSError(domain: "Invalid response", code: -1)
      }

      Logger.log(.api, "Response status: \(httpResponse.statusCode)")

      guard httpResponse.statusCode == 200 else {
        let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
        Logger.error(.api, "Failed to fetch API keys: \(errorText)")
        throw NSError(domain: errorText, code: httpResponse.statusCode)
      }

      struct Response: Codable {
        let keys: [APIKey]
      }

      let decoder = JSONDecoder()
      let result = try decoder.decode(Response.self, from: data)
      apiKeys = result.keys
      lastUpdated = Date()

      Logger.success(.api, "Loaded \(apiKeys.count) API keys")
    } catch {
      Logger.error(.api, "Failed to load API keys: \(error.localizedDescription)")
      lastError = error.localizedDescription
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
        await loadAPIKeys(authToken: authToken)
      }
    }
  }

  func stopAutoRefresh() {
    autoRefreshTask?.cancel()
    autoRefreshTask = nil
  }

  @discardableResult
  func createAPIKey(name: String, authToken: String) async -> APIKey? {
    do {
      let url = URL(string: "\(apiURL)/api-keys")!
      var request = URLRequest(url: url)
      request.httpMethod = "POST"
      request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")

      let body = ["name": name]
      request.httpBody = try JSONEncoder().encode(body)

      Logger.log(.api, "Creating API key: \(name)")

      let (data, response) = try await urlSession.data(for: request)

      guard let httpResponse = response as? HTTPURLResponse else {
        throw NSError(domain: "Invalid response", code: -1)
      }

      guard httpResponse.statusCode == 200 else {
        let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
        Logger.error(.api, "Failed to create API key: \(errorText)")
        throw NSError(domain: errorText, code: httpResponse.statusCode)
      }

      let decoder = JSONDecoder()
      let key = try decoder.decode(APIKey.self, from: data)

      Logger.success(.api, "Created API key: \(name)")

      await loadAPIKeys(authToken: authToken)

      return key
    } catch {
      Logger.error(.api, "Failed to create API key: \(error.localizedDescription)")
      lastError = error.localizedDescription
      return nil
    }
  }

  func updateAPIKey(key: String, name: String, authToken: String) async {
    do {
      let url = URL(string: "\(apiURL)/api-keys/\(key)")!
      var request = URLRequest(url: url)
      request.httpMethod = "PATCH"
      request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")

      let body = ["name": name]
      request.httpBody = try JSONEncoder().encode(body)

      Logger.log(.api, "Updating API key name: \(name)")

      let (data, response) = try await urlSession.data(for: request)

      guard let httpResponse = response as? HTTPURLResponse else {
        throw NSError(domain: "Invalid response", code: -1)
      }

      guard httpResponse.statusCode == 200 else {
        let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
        Logger.error(.api, "Failed to update API key: \(errorText)")
        throw NSError(domain: errorText, code: httpResponse.statusCode)
      }

      Logger.success(.api, "Updated API key name")

      await loadAPIKeys(authToken: authToken)
    } catch {
      Logger.error(.api, "Failed to update API key: \(error.localizedDescription)")
      lastError = error.localizedDescription
    }
  }

  func deleteAPIKey(key: String, authToken: String) async {
    do {
      let url = URL(string: "\(apiURL)/api-keys/\(key)")!
      var request = URLRequest(url: url)
      request.httpMethod = "DELETE"
      request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")

      Logger.log(.api, "Deleting API key: \(key)")

      let (data, response) = try await urlSession.data(for: request)

      guard let httpResponse = response as? HTTPURLResponse else {
        throw NSError(domain: "Invalid response", code: -1)
      }

      guard httpResponse.statusCode == 200 else {
        let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
        Logger.error(.api, "Failed to delete API key: \(errorText)")
        throw NSError(domain: errorText, code: httpResponse.statusCode)
      }

      Logger.success(.api, "Deleted API key")

      await loadAPIKeys(authToken: authToken)
    } catch {
      Logger.error(.api, "Failed to delete API key: \(error.localizedDescription)")
      lastError = error.localizedDescription
    }
  }
}
