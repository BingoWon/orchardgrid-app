import Foundation

/// Thin REST client that centralizes auth, HTTP status checks, JSON coding,
/// and error classification. Every request fetches a fresh bearer token from
/// `tokenProvider` — there is no token caching.
struct APIClient: Sendable {
  let baseURL: URL
  let session: URLSession
  let tokenProvider: @Sendable () async -> String?

  init(
    baseURL: URL,
    session: URLSession = Config.urlSession,
    tokenProvider: @escaping @Sendable () async -> String?
  ) {
    self.baseURL = baseURL
    self.session = session
    self.tokenProvider = tokenProvider
  }

  // MARK: - Public methods

  func get<T: Decodable>(
    _ path: String,
    query: [URLQueryItem] = []
  ) async throws -> T {
    let data = try await perform("GET", path, query: query, body: nil)
    return try decode(T.self, from: data)
  }

  @discardableResult
  func post<T: Decodable, B: Encodable>(
    _ path: String,
    body: B
  ) async throws -> T {
    let data = try await perform("POST", path, body: encode(body))
    return try decode(T.self, from: data)
  }

  func patch<B: Encodable>(_ path: String, body: B) async throws {
    _ = try await perform("PATCH", path, body: encode(body))
  }

  func delete(_ path: String) async throws {
    _ = try await perform("DELETE", path, body: nil)
  }

  // MARK: - Core request

  private func perform(
    _ method: String,
    _ path: String,
    query: [URLQueryItem] = [],
    body: Data?
  ) async throws -> Data {
    guard let token = await tokenProvider() else {
      throw APIError.local(String(localized: "Not authenticated."))
    }

    let url = try makeURL(path: path, query: query)
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    if let body {
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.httpBody = body
    }

    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await session.data(for: request)
    } catch {
      throw APIError.classify(error)
    }

    guard let http = response as? HTTPURLResponse else {
      throw APIError.local(String(localized: "Invalid server response."))
    }

    guard (200..<300).contains(http.statusCode) else {
      throw APIError.http(status: http.statusCode, message: Self.extractMessage(from: data))
    }

    return data
  }

  // MARK: - Helpers

  private func makeURL(path: String, query: [URLQueryItem]) throws -> URL {
    let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
    let url = baseURL.appending(path: trimmed)
    guard !query.isEmpty else { return url }
    guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
      throw APIError.local(String(localized: "Invalid URL."))
    }
    components.queryItems = query
    guard let composed = components.url else {
      throw APIError.local(String(localized: "Invalid URL."))
    }
    return composed
  }

  private func encode<B: Encodable>(_ body: B) throws -> Data {
    do {
      return try JSONEncoder().encode(body)
    } catch {
      throw APIError.local(String(localized: "Failed to encode request."))
    }
  }

  private func decode<T: Decodable>(_: T.Type, from data: Data) throws -> T {
    do {
      return try JSONDecoder().decode(T.self, from: data)
    } catch {
      throw APIError.classify(error)
    }
  }

  /// Extracts a human-readable error from a server response body.
  /// Accepts `{"error": "..."}` regardless of neighboring field types,
  /// then falls back to raw UTF-8, then nil.
  private static func extractMessage(from data: Data) -> String? {
    if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let message = object["error"] as? String, !message.isEmpty
    {
      return message
    }
    if let text = String(data: data, encoding: .utf8), !text.isEmpty {
      return text
    }
    return nil
  }
}
