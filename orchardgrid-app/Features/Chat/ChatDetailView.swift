/**
 * ChatDetailView.swift
 * Chat interface with streaming Apple Intelligence responses
 */

import SwiftUI

struct ChatDetailView: View {
  let conversationId: UUID
  @Environment(ChatManager.self) private var chatManager
  @State private var inputText = ""
  @FocusState private var isInputFocused: Bool

  private var conversation: Conversation? {
    chatManager.conversation(for: conversationId)
  }

  private var isStreaming: Bool {
    chatManager.respondingConversationId == conversationId
  }

  var body: some View {
    VStack(spacing: 0) {
      messageList
      Divider()
      inputBar
    }
    .navigationTitle(conversation?.title ?? "Chat")
    .toolbarRole(.editor)
    .toolbarTitleDisplayMode(.inlineLarge)
    .onDisappear { cleanupIfEmpty() }
  }

  // MARK: - Message List

  private var messageList: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(spacing: 12) {
          if let messages = conversation?.messages, !messages.isEmpty {
            ForEach(messages) { message in
              MessageBubble(message: message)
                .id(message.id)
            }
          } else if !isStreaming {
            welcomePrompt
          }

          // Live streaming bubble
          if isStreaming, !chatManager.streamingText.isEmpty {
            MessageBubble(
              message: Message(role: .assistant, content: chatManager.streamingText)
            )
            .id("streaming")
          }

          // Typing indicator
          if isStreaming, chatManager.streamingText.isEmpty {
            HStack {
              TypingIndicator()
              Spacer()
            }
            .id("typing")
          }
        }
        .padding()
      }
      .onChange(of: conversation?.messages.count) { _, _ in
        scrollToBottom(proxy)
      }
      .onChange(of: isStreaming) { _, streaming in
        if streaming { scrollToBottom(proxy) }
      }
      .onAppear {
        scrollToBottom(proxy)
      }
    }
  }

  // MARK: - Welcome Prompt

  private var welcomePrompt: some View {
    VStack(spacing: 16) {
      Image(systemName: "apple.intelligence")
        .font(.system(size: 40))
        .foregroundStyle(.secondary)

      Text("Apple Intelligence")
        .font(.title3)
        .fontWeight(.semibold)

      Text("Ask me anything — powered entirely on-device.")
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 60)
  }

  // MARK: - Input Bar

  private var inputBar: some View {
    HStack(alignment: .bottom, spacing: 12) {
      TextField("Message", text: $inputText, axis: .vertical)
        .textFieldStyle(.plain)
        .lineLimit(1 ... 5)
        .focused($isInputFocused)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onKeyPress(.return, phases: .down) { press in
          if press.modifiers.contains(.shift) {
            return .ignored // insert newline
          }
          sendMessage()
          return .handled
        }

      if chatManager.isResponding {
        Button {
          chatManager.stopResponding()
        } label: {
          Image(systemName: "stop.circle.fill")
            .font(.system(size: 32))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(.red)
        }
        .buttonStyle(.plain)
      } else {
        Button {
          sendMessage()
        } label: {
          Image(systemName: "arrow.up.circle.fill")
            .font(.system(size: 32))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(canSend ? Color.blue : Color.gray.opacity(0.3))
        }
        .disabled(!canSend)
        .buttonStyle(.plain)
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
  }

  // MARK: - Helpers

  private var canSend: Bool {
    !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !chatManager.isResponding
      && chatManager.isModelAvailable
  }

  private func sendMessage() {
    let content = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !content.isEmpty else { return }
    inputText = ""
    chatManager.sendMessage(content, in: conversationId)
  }

  private func scrollToBottom(_ proxy: ScrollViewProxy) {
    withAnimation(.easeOut(duration: 0.2)) {
      if isStreaming {
        proxy.scrollTo(
          chatManager.streamingText.isEmpty ? "typing" : "streaming",
          anchor: .bottom
        )
      } else if let lastId = conversation?.messages.last?.id {
        proxy.scrollTo(lastId, anchor: .bottom)
      }
    }
  }

  /// Remove empty conversations when navigating away without sending
  private func cleanupIfEmpty() {
    if let conv = conversation, conv.messages.isEmpty {
      chatManager.deleteConversation(id: conv.id)
    }
  }
}

// MARK: - Message Bubble

private struct MessageBubble: View {
  let message: Message

  var body: some View {
    HStack {
      if message.role == .user { Spacer(minLength: 48) }

      Text(message.content)
        .font(.body)
        .textSelection(.enabled)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .foregroundStyle(message.role == .user ? .white : .primary)
        .background(bubbleBackground)

      if message.role == .assistant { Spacer(minLength: 48) }
    }
  }

  @ViewBuilder
  private var bubbleBackground: some View {
    if message.role == .user {
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .fill(.blue.gradient)
    } else {
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .fill(.fill.tertiary)
    }
  }
}

// MARK: - Typing Indicator

private struct TypingIndicator: View {
  @State private var isAnimating = false

  var body: some View {
    HStack(spacing: 5) {
      ForEach(0 ..< 3, id: \.self) { index in
        Circle()
          .fill(.secondary)
          .frame(width: 7, height: 7)
          .scaleEffect(isAnimating ? 1.0 : 0.5)
          .opacity(isAnimating ? 1.0 : 0.4)
          .animation(
            .easeInOut(duration: 0.5)
              .repeatForever(autoreverses: true)
              .delay(Double(index) * 0.15),
            value: isAnimating
          )
      }
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 12)
    .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    .onAppear { isAnimating = true }
  }
}

#Preview {
  NavigationStack {
    ChatDetailView(conversationId: UUID())
      .environment(ChatManager())
  }
}
