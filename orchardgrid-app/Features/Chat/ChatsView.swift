import SwiftUI

struct ChatsView: View {
  @Environment(ChatManager.self) private var chatManager
  @State private var selectedConversationId: UUID?
  @State private var showDeleteAll = false

  var body: some View {
    Group {
      if !chatManager.isModelAvailable {
        ScrollView {
          AIStatusCard(availability: chatManager.modelAvailability)
            .padding(Constants.standardPadding)
        }
      } else if chatManager.conversations.isEmpty {
        emptyState
      } else {
        conversationList
      }
    }
    .navigationTitle("Chats")
    .toolbarRole(.editor)
    .toolbarTitleDisplayMode(.inlineLarge)
    .contentToolbar {
      if chatManager.isModelAvailable, !chatManager.conversations.isEmpty {
        HStack(spacing: 12) {
          Menu {
            Button(role: .destructive) {
              showDeleteAll = true
            } label: {
              Label("Delete All", systemImage: "trash")
            }
          } label: {
            Image(systemName: "ellipsis.circle")
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
    GlassEffectContainer {
      List {
        ForEach(chatManager.conversations) { conversation in
          Button {
            selectedConversationId = conversation.id
          } label: {
            ConversationRow(conversation: conversation)
          }
          .buttonStyle(.plain)
          .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
          .listRowBackground(Color.clear)
          .listRowSeparator(.hidden)
          .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
              chatManager.deleteConversation(id: conversation.id)
            } label: {
              Label("Delete", systemImage: "trash")
            }
          }
        }
      }
      .listStyle(.plain)
      .scrollContentBackground(.hidden)
    }
  }

  // MARK: - Empty State

  private var emptyState: some View {
    VStack(spacing: 24) {
      Image(systemName: "apple.intelligence")
        .font(.system(size: 52))
        .foregroundStyle(.secondary)
        .symbolColorRenderingMode(.gradient)

      VStack(spacing: 6) {
        Text("No Conversations")
          .font(.title3.weight(.semibold))
        Text("Start a new chat with Apple Intelligence")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }

      Button {
        let conv = chatManager.createConversation()
        selectedConversationId = conv.id
      } label: {
        Label("New Chat", systemImage: "plus")
          .frame(minWidth: 160)
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.large)
      .padding(.top, 4)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

// MARK: - Conversation Row

private struct ConversationRow: View {
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
