/**
 * ChatManager.swift
 * Manages on-device chat conversations with Apple Intelligence
 */

import Foundation
@preconcurrency import FoundationModels

@MainActor
@Observable
final class ChatManager {
  private(set) var conversations: [Conversation] = []
  private(set) var isResponding = false
  private(set) var streamingText = ""
  private(set) var respondingConversationId: UUID?

  private var responseTask: Task<Void, Never>?

  private var sessions: [UUID: LanguageModelSession] = [:]
  private let model = SystemLanguageModel.default

  private static let systemInstructions = """
    You are a helpful, friendly AI assistant powered by Apple Intelligence. \
    Be concise, clear, and informative in your responses.
    """

  // MARK: - Model Availability

  var modelAvailability: SystemLanguageModel.Availability {
    model.availability
  }

  var isModelAvailable: Bool {
    if case .available = model.availability { return true }
    return false
  }

  // MARK: - Init

  init() {
    loadConversations()
  }

  // MARK: - Conversation Management

  @discardableResult
  func createConversation() -> Conversation {
    let conversation = Conversation()
    conversations.insert(conversation, at: 0)
    save()
    return conversation
  }

  func deleteConversation(id: UUID) {
    conversations.removeAll { $0.id == id }
    sessions.removeValue(forKey: id)
    save()
  }

  func clearAllConversations() {
    conversations.removeAll()
    sessions.removeAll()
    save()
  }

  func conversation(for id: UUID) -> Conversation? {
    conversations.first { $0.id == id }
  }

  // MARK: - Messaging

  func sendMessage(_ content: String, in conversationId: UUID) {
    guard let index = conversations.firstIndex(where: { $0.id == conversationId }),
          !isResponding, isModelAvailable
    else { return }

    // Add user message
    let userMessage = Message(role: .user, content: content)
    conversations[index].messages.append(userMessage)
    conversations[index].updateTitleIfNeeded()
    conversations[index].updatedAt = Date()
    save()

    // Begin streaming
    isResponding = true
    streamingText = ""
    respondingConversationId = conversationId

    responseTask = Task {
      defer {
        isResponding = false
        streamingText = ""
        respondingConversationId = nil
        responseTask = nil
      }

      do {
        let session = getOrCreateSession(for: conversationId)
        let stream = session.streamResponse(to: content)
        var fullContent = ""

        for try await snapshot in stream {
          try Task.checkCancellation()
          fullContent = snapshot.content
          streamingText = fullContent
        }

        // Append completed assistant message
        appendAssistantMessage(fullContent, to: conversationId)
      } catch is CancellationError {
        // Save partial content on stop
        let partial = streamingText
        if !partial.isEmpty {
          appendAssistantMessage(partial, to: conversationId)
        }
      } catch {
        Logger.error(.app, "Chat error: \(error.localizedDescription)")
        appendAssistantMessage(
          "Sorry, an error occurred: \(error.localizedDescription)",
          to: conversationId
        )
      }
    }
  }

  func stopResponding() {
    responseTask?.cancel()
  }

  private func appendAssistantMessage(_ content: String, to conversationId: UUID) {
    guard let idx = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
    let message = Message(role: .assistant, content: content)
    conversations[idx].messages.append(message)
    conversations[idx].updatedAt = Date()
    moveToTop(conversationId)
    save()
  }

  // MARK: - Session Management

  private func getOrCreateSession(for conversationId: UUID) -> LanguageModelSession {
    if let session = sessions[conversationId] {
      return session
    }

    let session: LanguageModelSession

    if let conversation = conversation(for: conversationId), !conversation.messages.isEmpty {
      // Rehydrate session from saved messages
      let transcript = buildTranscript(from: conversation.messages)
      session = LanguageModelSession(transcript: transcript)
    } else {
      session = LanguageModelSession(instructions: Self.systemInstructions)
    }

    sessions[conversationId] = session
    return session
  }

  /// Build Transcript from saved messages — mirrors LLMProcessor.buildTranscript
  private func buildTranscript(from messages: [Message]) -> Transcript {
    var entries: [Transcript.Entry] = []

    let instructions = Transcript.Instructions(
      segments: [.text(.init(content: Self.systemInstructions))],
      toolDefinitions: []
    )
    entries.append(.instructions(instructions))

    for message in messages {
      switch message.role {
      case .user:
        let prompt = Transcript.Prompt(
          segments: [.text(.init(content: message.content))]
        )
        entries.append(.prompt(prompt))

      case .assistant:
        let response = Transcript.Response(
          assetIDs: [],
          segments: [.text(.init(content: message.content))]
        )
        entries.append(.response(response))
      }
    }

    return Transcript(entries: entries)
  }

  private func moveToTop(_ conversationId: UUID) {
    guard let index = conversations.firstIndex(where: { $0.id == conversationId }),
          index != 0
    else { return }
    let conversation = conversations.remove(at: index)
    conversations.insert(conversation, at: 0)
  }

  // MARK: - Persistence

  private static var storageURL: URL {
    FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("chats.json")
  }

  private func save() {
    do {
      let data = try JSONEncoder().encode(conversations)
      try data.write(to: Self.storageURL, options: .atomic)
    } catch {
      Logger.error(.app, "Failed to save chats: \(error.localizedDescription)")
    }
  }

  private func loadConversations() {
    let url = Self.storageURL
    guard FileManager.default.fileExists(atPath: url.path) else { return }
    do {
      let data = try Data(contentsOf: url)
      conversations = try JSONDecoder().decode([Conversation].self, from: data)
      Logger.success(.app, "Loaded \(conversations.count) conversations")
    } catch {
      Logger.error(.app, "Failed to load chats: \(error.localizedDescription)")
    }
  }
}
