/**
 * ChatModels.swift
 * Data models for on-device chat conversations
 */

import Foundation

// MARK: - Shared Image Storage

enum ChatImages {
  static var directory: URL {
    FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("chat-images")
  }

  static func fileExtension(for data: Data) -> String {
    guard data.count >= 2 else { return "dat" }
    switch (data[0], data[1]) {
    case (0x89, 0x50): return "png"
    case (0xFF, 0xD8): return "jpg"
    case (0x47, 0x49): return "gif"
    default: return "img"
    }
  }
}

// MARK: - Message

enum MessageRole: String, Codable, Sendable {
  case user
  case assistant
}

struct Message: Identifiable, Codable, Sendable {
  let id: UUID
  let role: MessageRole
  let content: String
  let imageFilenames: [String]
  let timestamp: Date

  init(role: MessageRole, content: String, imageFilenames: [String] = []) {
    id = UUID()
    self.role = role
    self.content = content
    self.imageFilenames = imageFilenames
    timestamp = Date()
  }

  var hasImages: Bool { !imageFilenames.isEmpty }
}

// MARK: - Conversation

struct Conversation: Identifiable, Codable, Sendable {
  let id: UUID
  var title: String
  var messages: [Message]
  let createdAt: Date
  var updatedAt: Date

  init(title: String = "New Chat") {
    id = UUID()
    self.title = title
    messages = []
    createdAt = Date()
    updatedAt = Date()
  }

  var needsTitleGeneration: Bool {
    title == "New Chat" && messages.contains(where: { $0.role == .assistant })
  }

  var titleSnippet: String {
    messages
      .filter { $0.role == .user || $0.role == .assistant }
      .prefix(4)
      .map { "\($0.role.rawValue): \(String($0.content.prefix(200)))" }
      .joined(separator: "\n")
  }
}
