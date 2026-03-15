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
      GlassEffectContainer(spacing: Constants.standardSpacing) {
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
    .navigationSubtitle(chatManager.conversations.isEmpty ? "" : "\(chatManager.conversations.count) conversations")
    .toolbarRole(.editor)
    .toolbarTitleDisplayMode(.inlineLarge)
    .contentToolbar {
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
    VStack(alignment: .leading, spacing: 8) {
      Text("History")
        .font(.subheadline)
        .fontWeight(.medium)
        .foregroundStyle(.tertiary)
        .padding(.leading, 4)

      ForEach(chatManager.conversations) { conversation in
        Button {
          selectedConversationId = conversation.id
        } label: {
          ConversationCard(conversation: conversation)
            .contentShape(Rectangle())
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
    ContentUnavailableView {
      Label("No Conversations", systemImage: "apple.intelligence")
    } description: {
      Text("Start a new chat with Apple Intelligence")
    } actions: {
      Button {
        let conv = chatManager.createConversation()
        selectedConversationId = conv.id
      } label: {
        Label("New Chat", systemImage: "plus")
      }
      .buttonStyle(.borderedProminent)
    }
    .frame(maxWidth: .infinity)
  }
}

// MARK: - Conversation Card

private struct ConversationCard: View {
  let conversation: Conversation

  var body: some View {
    HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 2) {
        Text(conversation.title)
          .font(.subheadline)
          .fontWeight(.medium)
          .lineLimit(1)

        Text(conversation.updatedAt, format: .relative(presentation: .named))
          .font(.caption)
          .foregroundStyle(.tertiary)
      }

      Spacer()

      HStack(spacing: 4) {
        Image(systemName: "bubble.left.fill")
          .font(.caption2)
        Text("\(conversation.messages.count)")
          .font(.caption)
          .monospacedDigit()
      }
      .foregroundStyle(.secondary)

      Image(systemName: "chevron.right")
        .font(.caption2)
        .fontWeight(.semibold)
        .foregroundStyle(.quaternary)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 10, style: .continuous))
  }
}

#Preview {
  NavigationStack {
    ChatsView()
      .environment(ChatManager())
  }
}
