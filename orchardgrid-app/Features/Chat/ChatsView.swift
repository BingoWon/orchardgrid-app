/**
 * ChatsView.swift
 * Conversation list — browse, create, and manage chat sessions
 */

import SwiftUI

struct ChatsView: View {
  @Environment(ChatManager.self) private var chatManager
  @State private var selectedConversationId: UUID?
  @State private var showDeleteAll = false

  var body: some View {
    ScrollView {
      GlassEffectContainer {
        VStack(alignment: .leading, spacing: Constants.standardSpacing) {
          if !chatManager.isModelAvailable {
            AIStatusCard(availability: chatManager.modelAvailability)
          } else if chatManager.conversations.isEmpty {
            emptyState
          } else {
            conversationList
          }
        }
        .padding(Constants.standardPadding)
      }
    }
    .navigationTitle("Chats")
    .toolbarRole(.editor)
    .toolbarTitleDisplayMode(.inlineLarge)
    .withPlatformToolbar {
      if chatManager.isModelAvailable {
        HStack(spacing: 12) {
          if !chatManager.conversations.isEmpty {
            Menu {
              Button(role: .destructive) {
                showDeleteAll = true
              } label: {
                Label("Delete All", systemImage: "trash")
              }
            } label: {
              Image(systemName: "ellipsis.circle")
            }
          }

          Button {
            let conv = chatManager.createConversation()
            selectedConversationId = conv.id
          } label: {
            Label("New Chat", systemImage: "plus")
          }
        }
      }
    }
    .navigationDestination(item: $selectedConversationId) { id in
      ChatDetailView(conversationId: id)
    }
    .alert("Delete All Conversations?", isPresented: $showDeleteAll) {
      Button("Cancel", role: .cancel) {}
      Button("Delete All", role: .destructive) {
        chatManager.clearAllConversations()
      }
    } message: {
      Text("This will permanently delete all conversations. This action cannot be undone.")
    }
  }

  // MARK: - Conversation List

  private var conversationList: some View {
    VStack(alignment: .leading, spacing: Constants.summaryCardSpacing) {
      Text("Conversations")
        .font(.headline)
        .foregroundStyle(.secondary)

      ForEach(chatManager.conversations) { conversation in
        Button {
          selectedConversationId = conversation.id
        } label: {
          ConversationCard(conversation: conversation)
        }
        .buttonStyle(.plain)
        .contextMenu {
          Button(role: .destructive) {
            chatManager.deleteConversation(id: conversation.id)
          } label: {
            Label("Delete", systemImage: "trash")
          }
        }
      }
    }
  }

  // MARK: - Empty State

  private var emptyState: some View {
    VStack(spacing: 16) {
      Image(systemName: "bubble.left.and.bubble.right")
        .font(.system(size: 48))
        .foregroundStyle(.secondary)

      Text("No Conversations")
        .font(.title2)
        .fontWeight(.semibold)

      Text("Start a new chat with Apple Intelligence")
        .font(.subheadline)
        .foregroundStyle(.secondary)

      Button {
        let conv = chatManager.createConversation()
        selectedConversationId = conv.id
      } label: {
        Text("New Chat")
          .font(.headline)
          .padding(.horizontal, 24)
          .padding(.vertical, 12)
      }
      .buttonStyle(.borderedProminent)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 60)
  }
}

// MARK: - Conversation Card

private struct ConversationCard: View {
  let conversation: Conversation

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text(conversation.title)
          .font(.headline)
          .lineLimit(1)

        Spacer()

        Text(conversation.updatedAt, format: .relative(presentation: .named))
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      if !conversation.lastMessagePreview.isEmpty {
        Text(conversation.lastMessagePreview)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .lineLimit(2)
      }

      HStack(spacing: 4) {
        Image(systemName: "bubble.left.fill")
          .font(.caption2)
        Text("\(conversation.messages.count)")
          .font(.caption)
      }
      .foregroundStyle(.tertiary)
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .glassEffect(in: .rect(cornerRadius: 12, style: .continuous))
  }
}

#Preview {
  NavigationStack {
    ChatsView()
      .environment(ChatManager())
  }
}
