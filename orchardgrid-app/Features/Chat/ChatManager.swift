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
  private let imageCollector = ImageCollector()

  private static let systemPrompt = """
    You are a helpful, friendly AI assistant powered by Apple Intelligence. \
    Be concise, clear, and informative in your responses. \
    You can generate images when asked using the generateImage tool.
    """

  private static let titlePrompt = """
    Generate a concise title (max 6 words) for this conversation. \
    Reply with ONLY the title, no quotes, no line breaks.
    """

  var modelAvailability: SystemLanguageModel.Availability {
    model.availability
  }

  var isModelAvailable: Bool {
    if case .available = model.availability { return true }
    return false
  }

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
    if let conv = conversations.first(where: { $0.id == id }) {
      cleanupImages(in: conv)
    }
    conversations.removeAll { $0.id == id }
    sessions.removeValue(forKey: id)
    save()
  }

  func clearAllConversations() {
    try? FileManager.default.removeItem(at: ChatImages.directory)
    conversations.removeAll()
    sessions.removeAll()
    save()
  }

  func conversation(for id: UUID) -> Conversation? {
    conversations.first { $0.id == id }
  }

  // MARK: - Messaging

  func sendMessage(_ content: String, imageFilenames: [String] = [], in conversationId: UUID) {
    guard let index = conversations.firstIndex(where: { $0.id == conversationId }),
          !isResponding, isModelAvailable
    else { return }

    let userMessage = Message(role: .user, content: content, imageFilenames: imageFilenames)
    conversations[index].messages.append(userMessage)
    conversations[index].updatedAt = Date()
    save()

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

      if let refFilename = imageFilenames.first {
        let refURL = ChatImages.directory.appendingPathComponent(refFilename)
        await imageCollector.setReferenceImage(refURL)
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

        let images = await imageCollector.flush()
        appendAssistantMessage(fullContent, imageFilenames: images, to: conversationId)
      } catch is CancellationError {
        let partial = streamingText
        let images = await imageCollector.flush()
        if !partial.isEmpty || !images.isEmpty {
          appendAssistantMessage(partial, imageFilenames: images, to: conversationId)
        }
      } catch {
        Logger.error(.app, "Chat error: \(error.localizedDescription)")
        let images = await imageCollector.flush()
        appendAssistantMessage(
          "Sorry, an error occurred: \(error.localizedDescription)",
          imageFilenames: images,
          to: conversationId
        )
      }
    }
  }

  func stopResponding() {
    responseTask?.cancel()
  }

  private func appendAssistantMessage(
    _ content: String,
    imageFilenames: [String] = [],
    to conversationId: UUID
  ) {
    guard let idx = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
    let message = Message(role: .assistant, content: content, imageFilenames: imageFilenames)
    conversations[idx].messages.append(message)
    conversations[idx].updatedAt = Date()
    moveToTop(conversationId)
    save()

    if conversations[idx].needsTitleGeneration {
      Task { await generateTitle(for: conversationId) }
    }
  }

  // MARK: - Title Generation

  private func generateTitle(for conversationId: UUID) async {
    guard let idx = conversations.firstIndex(where: { $0.id == conversationId }),
          conversations[idx].needsTitleGeneration
    else { return }

    let snippet = conversations[idx].titleSnippet
    guard !snippet.isEmpty else { return }

    do {
      let session = LanguageModelSession(instructions: Self.titlePrompt)
      let response = try await session.respond(to: snippet)
      let title = response.content
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))

      guard !title.isEmpty,
            let current = conversations.firstIndex(where: { $0.id == conversationId }),
            conversations[current].needsTitleGeneration
      else { return }

      conversations[current].title = title
      save()
    } catch {
      Logger.error(.app, "Title generation failed: \(error.localizedDescription)")
      fallbackTitle(for: conversationId)
    }
  }

  private func fallbackTitle(for conversationId: UUID) {
    guard let idx = conversations.firstIndex(where: { $0.id == conversationId }),
          conversations[idx].title == "New Chat",
          let first = conversations[idx].messages.first(where: { $0.role == .user })
    else { return }

    let trimmed = first.content.trimmingCharacters(in: .whitespacesAndNewlines)
    conversations[idx].title = trimmed.count > 30 ? String(trimmed.prefix(30)) + "…" : trimmed
    save()
  }

  // MARK: - Session Management

  private func getOrCreateSession(for conversationId: UUID) -> LanguageModelSession {
    if let session = sessions[conversationId] {
      return session
    }

    let tool = ImageGenerationTool(collector: imageCollector)
    let session: LanguageModelSession

    if let conversation = conversation(for: conversationId), !conversation.messages.isEmpty {
      let history = conversation.messages.prefix(20)
        .map { "\($0.role == .user ? "User" : "Assistant"): \(String($0.content.prefix(500)))" }
        .joined(separator: "\n")
      let instructions = """
        \(Self.systemPrompt)

        Previous conversation:
        \(history)
        """
      session = LanguageModelSession(tools: [tool], instructions: instructions)
    } else {
      session = LanguageModelSession(tools: [tool], instructions: Self.systemPrompt)
    }

    sessions[conversationId] = session
    return session
  }

  // MARK: - Private Helpers

  private func moveToTop(_ conversationId: UUID) {
    guard let index = conversations.firstIndex(where: { $0.id == conversationId }),
          index != 0
    else { return }
    let conversation = conversations.remove(at: index)
    conversations.insert(conversation, at: 0)
  }

  private func cleanupImages(in conversation: Conversation) {
    let dir = ChatImages.directory
    for filename in conversation.messages.flatMap(\.imageFilenames) {
      try? FileManager.default.removeItem(at: dir.appendingPathComponent(filename))
    }
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
