import Foundation

// MARK: - Cloud API Client

/// Typed client for management-plane endpoints (`/api/*`) — distinct from
/// `RemoteEngine` which speaks OpenAI-compatible `/v1/*`. Shares the same
/// Bearer-token + host convention.
public struct CloudAPI: Sendable {
  public let base: URL
  public let token: String
  private let session = URLSession.shared

  public init(host: String, token: String) throws {
    guard let url = URL(string: host) else { throw OGError.usage("invalid host: \(host)") }
    guard !token.isEmpty else {
      throw OGError.runtime("not logged in — run `og login` first")
    }
    self.base = url
    self.token = token
  }

  // MARK: - Endpoints

  public func me() async throws -> Me {
    try await getJSON("/api/me")
  }

  public func listAPIKeys() async throws -> [APIKeyInfo] {
    struct Envelope: Decodable { let keys: [APIKeyInfo] }
    let envelope: Envelope = try await getJSON("/api/api-keys")
    return envelope.keys
  }

  public func createAPIKey(
    name: String?,
    scope: String = "inference",
    deviceLabel: String? = nil
  ) async throws -> APIKeyInfo {
    let body = CreateKeyBody(name: name, scope: scope, device_label: deviceLabel)
    return try await postJSON("/api/api-keys", body: body)
  }

  public func deleteAPIKey(hint: String) async throws {
    _ = try await request(
      path: "/api/api-keys/\(hint)", method: "DELETE", body: Optional<String>.none
    )
  }

  public func listDevices() async throws -> [DeviceInfo] {
    try await getJSON("/api/devices")
  }

  public func logs(
    limit: Int = 50,
    offset: Int = 0,
    role: String? = nil,
    status: String? = nil
  ) async throws -> LogPage {
    var query: [URLQueryItem] = [
      URLQueryItem(name: "limit", value: String(limit)),
      URLQueryItem(name: "offset", value: String(offset)),
    ]
    if let role { query.append(URLQueryItem(name: "role", value: role)) }
    if let status { query.append(URLQueryItem(name: "status", value: status)) }
    return try await getJSON("/api/logs", query: query)
  }

  // MARK: - Transport

  private func getJSON<T: Decodable>(
    _ path: String, query: [URLQueryItem] = []
  ) async throws -> T {
    let data = try await request(
      path: path, method: "GET", query: query, body: Optional<String>.none)
    return try JSONDecoder().decode(T.self, from: data)
  }

  private func postJSON<In: Encodable, Out: Decodable>(
    _ path: String, body: In
  ) async throws -> Out {
    let data = try await request(path: path, method: "POST", body: body)
    return try JSONDecoder().decode(Out.self, from: data)
  }

  private func request<In: Encodable>(
    path: String,
    method: String,
    query: [URLQueryItem] = [],
    body: In?
  ) async throws -> Data {
    var components = URLComponents(url: base, resolvingAgainstBaseURL: false)!
    components.path = path
    if !query.isEmpty { components.queryItems = query }
    guard let url = components.url else {
      throw OGError.runtime("invalid URL for \(path)")
    }

    var req = URLRequest(url: url)
    req.httpMethod = method
    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    if let body {
      req.setValue("application/json", forHTTPHeaderField: "Content-Type")
      req.httpBody = try JSONEncoder().encode(body)
    }

    let (data, response): (Data, URLResponse)
    do {
      (data, response) = try await session.data(for: req)
    } catch {
      throw OGError.serverUnreachable
    }
    guard let http = response as? HTTPURLResponse else {
      throw OGError.runtime("invalid response")
    }
    if !(200...299).contains(http.statusCode) {
      throw OGError.fromHTTP(status: http.statusCode, body: data)
    }
    return data
  }
}

// MARK: - Wire Types

public struct Me: Codable, Sendable {
  public let id: String
  public let isAdmin: Bool
}

public struct APIKeyInfo: Codable, Sendable {
  public let key: String?  // only present on POST /api-keys
  public let keyHint: String
  public let name: String?
  public let scope: String?
  public let deviceLabel: String?
  public let createdAt: Int64
  public let lastUsedAt: Int64?

  enum CodingKeys: String, CodingKey {
    case key
    case keyHint = "key_hint"
    case name, scope
    case deviceLabel = "device_label"
    case createdAt = "created_at"
    case lastUsedAt = "last_used_at"
  }
}

public struct DeviceInfo: Codable, Sendable {
  public let id: String
  public let platform: String
  public let deviceName: String?
  public let chipModel: String?
  public let isOnline: Bool
  public let lastHeartbeat: Int64?
  public let logsProcessed: Int
  public let capabilities: [String]

  enum CodingKeys: String, CodingKey {
    case id, platform
    case deviceName = "device_name"
    case chipModel = "chip_model"
    case isOnline = "is_online"
    case lastHeartbeat = "last_heartbeat"
    case logsProcessed = "logs_processed"
    case capabilities
  }
}

public struct LogPage: Codable, Sendable {
  public let logs: [LogEntry]
  public let total: Int
  public let limit: Int
  public let offset: Int
}

public struct LogEntry: Codable, Sendable {
  public let id: String
  public let capability: String?
  public let status: String
  public let role: String?
  public let promptTokens: Int?
  public let completionTokens: Int?
  public let createdAt: Int64
  public let durationMs: Int?

  enum CodingKeys: String, CodingKey {
    case id, capability, status, role
    case promptTokens = "prompt_tokens"
    case completionTokens = "completion_tokens"
    case createdAt = "created_at"
    case durationMs = "duration_ms"
  }
}

private struct CreateKeyBody: Encodable {
  let name: String?
  let scope: String
  let device_label: String?
}
