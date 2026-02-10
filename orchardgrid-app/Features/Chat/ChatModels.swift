/**
 * ChatModels.swift
 * Data models for on-device chat conversations
 */

import Foundation

// MARK: - Message

enum MessageRole: String, Codable, Sendable {
  case user
  case assistant
}

struct Message: Identifiable, Codable, Sendable {
  let id: UUID
  let role: MessageRole
  let content: String
  let timestamp: Date

  init(role: MessageRole, content: String) {
    id = UUID()
    self.role = role
    self.content = content
    timestamp = Date()
  }
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

  var lastMessagePreview: String {
    messages.last?.content ?? ""
  }

  /// Auto-generate title from first user message
  mutating func updateTitleIfNeeded() {
    guard title == "New Chat",
          let first = messages.first(where: { $0.role == .user })
    else { return }

    let trimmed = first.content.trimmingCharacters(in: .whitespacesAndNewlines)
    title = trimmed.count > 30 ? String(trimmed.prefix(30)) + "…" : trimmed
  }
}
