import Foundation

struct ComputeTask: Identifiable, Codable {
  let id: String
  let userId: String
  let deviceId: String?
  let status: String
  let requestPayload: String?
  let responsePayload: String?
  let errorMessage: String?
  let createdAt: Int
  let startedAt: Int?
  let completedAt: Int?
  let durationMs: Int?

  enum CodingKeys: String, CodingKey {
    case id
    case userId = "user_id"
    case deviceId = "device_id"
    case status
    case requestPayload = "request_payload"
    case responsePayload = "response_payload"
    case errorMessage = "error_message"
    case createdAt = "created_at"
    case startedAt = "started_at"
    case completedAt = "completed_at"
    case durationMs = "duration_ms"
  }

  var createdDate: Date {
    Date(timeIntervalSince1970: TimeInterval(createdAt) / 1000)
  }

  var durationText: String {
    guard let ms = durationMs else { return "-" }
    if ms < 1000 {
      return "\(ms)ms"
    }
    return String(format: "%.2fs", Double(ms) / 1000)
  }
}

struct TasksResponse: Codable {
  let tasks: [ComputeTask]
  let total: Int
  let limit: Int
  let offset: Int
}
