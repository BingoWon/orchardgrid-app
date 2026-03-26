import Foundation
@preconcurrency import FoundationModels

@MainActor
@Observable
final class ChatManager {
  private(set) var conversations: [Conversation] = []
  private(set) var isResponding = false
  private(set) var streamingText = ""
  private(set) var respondingConversationId: UUID?
  private(set) var contextSize = 4096
  private(set) var conversationTokenCounts: [UUID: Int] = [:]

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

  /// Reserve tokens for the user's next prompt and the model's response.
  private static let tokenReserve = 512

  var modelAvailability: SystemLanguageModel.Availability {
    model.availability
  }

  var isModelAvailable: Bool {
    if case .available = model.availability { return true }
    return false
  }

  init() {
    loadConversations()
    Task { contextSize = (try? await model.contextSize) ?? 4096 }
  }

  // MARK: - Token Usage Info

  func tokenUsageInfo(for conversationId: UUID) -> (tokens: Int, contextSize: Int)? {
    guard let count = conversationTokenCounts[conversationId] else { return nil }
    return (count, contextSize)
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
    conversationTokenCounts.removeValue(forKey: id)
    save()
  }

  func clearAllConversations() {
    try? FileManager.default.removeItem(at: ChatImages.directory)
    conversations.removeAll()
    sessions.removeAll()
    conversationTokenCounts.removeAll()
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
        let session = await buildSession(for: conversationId)
        let stream = session.streamResponse(to: content)
        var fullContent = ""

        for try await snapshot in stream {
          try Task.checkCancellation()
          fullContent = snapshot.content
          streamingText = fullContent
        }

        // Measure transcript token usage after response
        if let usage = try? await model.tokenUsage(for: session.transcript) {
          conversationTokenCounts[conversationId] = usage.tokenCount
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
        Logger.error(.app, "Chat error: \(error)")
        let images = await imageCollector.flush()
        let desc = "\(error)"
        let userMessage: String
        if desc.contains("GenerationError") {
          userMessage =
            "Apple Intelligence could not generate a response. "
            + "Please ensure Apple Intelligence is fully set up in "
            + "Settings → Apple Intelligence & Siri, and that the "
            + "on-device model has finished downloading."
        } else {
          userMessage = "Sorry, an error occurred: \(error.localizedDescription)"
        }
        appendAssistantMessage(userMessage, imageFilenames: images, to: conversationId)
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

  // MARK: - Smart Session Builder

  /// Builds a `LanguageModelSession` with as much conversation history as fits
  /// within the context window, prioritizing the most recent messages.
  private func buildSession(for conversationId: UUID) async -> LanguageModelSession {
    if let session = sessions[conversationId] {
      return session
    }

    let tool = ImageGenerationTool(collector: imageCollector)
    let processor = LLMProcessor()

    guard let conversation = conversation(for: conversationId), !conversation.messages.isEmpty
    else {
      let session = LanguageModelSession(tools: [tool], instructions: Self.systemPrompt)
      sessions[conversationId] = session
      return session
    }

    // Measure baseline: system prompt + tool definitions
    let baselineTokens = await processor.measureInstructions(
      Self.systemPrompt, tools: [tool])
    let historyBudget = contextSize - baselineTokens - Self.tokenReserve
    var messages = Array(conversation.messages)

    // Iteratively trim until history fits within budget
    while !messages.isEmpty {
      let history = Self.formatHistory(messages)
      let instructions = "\(Self.systemPrompt)\n\nPrevious conversation:\n\(history)"
      let instructionTokens = await processor.measureInstructions(
        instructions, tools: [tool])

      if instructionTokens <= contextSize - Self.tokenReserve {
        let session = LanguageModelSession(tools: [tool], instructions: instructions)
        sessions[conversationId] = session
        return session
      }

      // Remove oldest quarter of messages
      let removeCount = max(1, messages.count / 4)
      messages = Array(messages.dropFirst(removeCount))
    }

    // Fallback: no history
    let session = LanguageModelSession(tools: [tool], instructions: Self.systemPrompt)
    sessions[conversationId] = session
    return session
  }

  private static func formatHistory(_ messages: [Message]) -> String {
    messages
      .map { "\($0.role == .user ? "User" : "Assistant"): \($0.content)" }
      .joined(separator: "\n")
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
