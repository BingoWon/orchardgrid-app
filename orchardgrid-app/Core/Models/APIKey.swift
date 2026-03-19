import Foundation

struct APIKey: Identifiable, Codable, Sendable {
  let key: String?
  let keyHint: String
  let name: String?
  let createdAt: Int
  let lastUsedAt: Int?

  var id: String { keyHint }

  var createdDate: Date {
    Date(timeIntervalSince1970: TimeInterval(createdAt) / 1000)
  }

  var lastUsedDate: Date? {
    lastUsedAt.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) }
  }

  enum CodingKeys: String, CodingKey {
    case key
    case keyHint = "key_hint"
    case name
    case createdAt = "created_at"
    case lastUsedAt = "last_used_at"
  }
}
