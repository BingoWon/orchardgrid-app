import Foundation

@MainActor
@Observable
final class APIKeysManager: Refreshable {
  private(set) var apiKeys: [APIKey] = []
  private(set) var isInitialLoading = true
  private(set) var isRefreshing = false
  private(set) var lastError: String?
  private(set) var lastUpdated: Date?

  private let apiURL = Config.apiBaseURL
  private let urlSession = Config.urlSession

  func loadAPIKeys(authToken: String, isManualRefresh: Bool = false) async {
    if apiKeys.isEmpty {
      isInitialLoading = true
    } else if isManualRefresh {
      isRefreshing = true
    }
    lastError = nil

    do {
      let url = URL(string: "\(apiURL)/api-keys")!
      var request = URLRequest(url: url)
      request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")

      let (data, response) = try await urlSession.data(for: request)

      guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
        let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
        throw NSError(domain: errorText, code: -1)
      }

      struct Response: Codable {
        let keys: [APIKey]
      }

      let result = try JSONDecoder().decode(Response.self, from: data)
      apiKeys = result.keys
      lastUpdated = Date()
    } catch is CancellationError {
      return
    } catch let error as URLError where error.code == .cancelled {
      return
    } catch {
      Logger.error(.api, "Failed to load API keys: \(error.localizedDescription)")
      lastError = error.localizedDescription
    }

    isInitialLoading = false
    isRefreshing = false
  }

  @discardableResult
  func createAPIKey(name: String, authToken: String) async -> APIKey? {
    do {
      let url = URL(string: "\(apiURL)/api-keys")!
      var request = URLRequest(url: url)
      request.httpMethod = "POST"
      request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.httpBody = try JSONEncoder().encode(["name": name])

      let (data, response) = try await urlSession.data(for: request)

      guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
        let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
        throw NSError(domain: errorText, code: -1)
      }

      let key = try JSONDecoder().decode(APIKey.self, from: data)
      await loadAPIKeys(authToken: authToken)
      return key
    } catch {
      Logger.error(.api, "Failed to create API key: \(error.localizedDescription)")
      lastError = error.localizedDescription
      return nil
    }
  }

  func updateAPIKey(hint: String, name: String, authToken: String) async {
    do {
      let encoded = hint.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? hint
      let url = URL(string: "\(apiURL)/api-keys/\(encoded)")!
      var request = URLRequest(url: url)
      request.httpMethod = "PATCH"
      request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.httpBody = try JSONEncoder().encode(["name": name])

      let (data, response) = try await urlSession.data(for: request)

      guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
        let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
        throw NSError(domain: errorText, code: -1)
      }

      await loadAPIKeys(authToken: authToken)
    } catch {
      Logger.error(.api, "Failed to update API key: \(error.localizedDescription)")
      lastError = error.localizedDescription
    }
  }

  func deleteAPIKey(hint: String, authToken: String) async {
    do {
      let encoded = hint.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? hint
      let url = URL(string: "\(apiURL)/api-keys/\(encoded)")!
      var request = URLRequest(url: url)
      request.httpMethod = "DELETE"
      request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")

      let (data, response) = try await urlSession.data(for: request)

      guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
        let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
        throw NSError(domain: errorText, code: -1)
      }

      await loadAPIKeys(authToken: authToken)
    } catch {
      Logger.error(.api, "Failed to delete API key: \(error.localizedDescription)")
      lastError = error.localizedDescription
    }
  }
}
