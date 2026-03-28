import Foundation

enum LogRole: String, Codable, Sendable, CaseIterable {
  case sent, served, local

  var label: String {
    switch self {
    case .sent: String(localized: "Sent")
    case .served: String(localized: "Served")
    case .local: String(localized: "Local")
    }
  }
}

struct ComputeTask: Identifiable, Codable, Sendable {
  let id: String
  let userId: String
  let deviceId: String?
  let capability: String?
  let status: String
  let requestPayload: String?
  let responsePayload: String?
  let errorMessage: String?
  let promptTokens: Int?
  let completionTokens: Int?
  let createdAt: Int
  let startedAt: Int?
  let completedAt: Int?
  let durationMs: Int?
  let role: LogRole?

  enum CodingKeys: String, CodingKey {
    case id
    case userId = "user_id"
    case deviceId = "device_id"
    case capability
    case status
    case requestPayload = "request_payload"
    case responsePayload = "response_payload"
    case errorMessage = "error_message"
    case promptTokens = "prompt_tokens"
    case completionTokens = "completion_tokens"
    case createdAt = "created_at"
    case startedAt = "started_at"
    case completedAt = "completed_at"
    case durationMs = "duration_ms"
    case role
  }

  var createdDate: Date {
    Date(timeIntervalSince1970: TimeInterval(createdAt) / 1000)
  }

  var durationText: String {
    guard let ms = durationMs else { return "—" }
    if ms < 1000 {
      return "\(ms)ms"
    }
    return String(format: "%.2fs", Double(ms) / 1000)
  }

  var tokensText: String {
    guard let p = promptTokens, let c = completionTokens else { return "—" }
    return "\(p) + \(c) = \(p + c)"
  }
}

struct TasksResponse: Codable, Sendable {
  let tasks: [ComputeTask]
  let total: Int
  let limit: Int
  let offset: Int
}
