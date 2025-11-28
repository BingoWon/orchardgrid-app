import SwiftUI
#if os(macOS)
  import AppKit
#else
  import UIKit
#endif

private let maskPrefixLength = 20
private let maskSuffixLength = 4
private let maskMinLength = 24

struct APIKeysView: View {
  @Environment(AuthManager.self) private var authManager
  @Environment(ObserverClient.self) private var observerClient
  @State private var manager = APIKeysManager()
  @State private var editingKey: String?
  @State private var editingName = ""
  @State private var visibleKeys: Set<String> = []
  @State private var showDeleteConfirmation = false
  @State private var keyToDelete: APIKey?
  @State private var copiedText: String?

  var body: some View {
    ScrollView {
      GlassEffectContainer {
        VStack(alignment: .leading, spacing: Constants.standardSpacing) {
          if authManager.isAuthenticated {
            authenticatedContent
          } else {
            GuestFeaturePrompt(
              icon: "key.fill",
              title: "Get Your API Keys",
              description: "Sign in to create API keys and access OrchardGrid from your applications.",
              benefits: [
                "Standard Chat Completion API format",
                "Works with popular AI tools",
                "Manage multiple API keys",
              ],
              buttonTitle: "Sign In to Create API Key"
            )
          }
        }
        .padding(Constants.standardPadding)
      }
    }
    .refreshable {
      guard let token = authManager.authToken else { return }
      await manager.loadAPIKeys(authToken: token, isManualRefresh: true)
    }
    .navigationTitle("API Keys")
    .toolbarRole(.editor)
    .toolbarTitleDisplayMode(.inlineLarge)
    .withPlatformToolbar {
      if authManager.isAuthenticated {
        HStack(spacing: 12) {
          if manager.isRefreshing {
            ProgressView()
              .controlSize(.small)
          }

          Button {
            createKey()
          } label: {
            Label("Create", systemImage: "plus")
          }
          .disabled(authManager.authToken == nil)
        }
      }
    }
    .task {
      guard let token = authManager.authToken else { return }
      await manager.loadAPIKeys(authToken: token)
    }
    .alert("Delete API Key?", isPresented: $showDeleteConfirmation) {
      Button("Cancel", role: .cancel) {}
      Button("Delete", role: .destructive) {
        if let key = keyToDelete {
          Task {
            guard let token = authManager.authToken else { return }
            await manager.deleteAPIKey(key: key.key, authToken: token)
          }
        }
      }
    } message: {
      if let key = keyToDelete {
        Text("Are you sure you want to delete \"\(key.name ?? "this API key")\"?")
      }
    }
  }

  // MARK: - Authenticated Content

  @ViewBuilder
  private var authenticatedContent: some View {
    // Status Bar
    HStack {
      HStack(spacing: 4) {
        Circle()
          .fill(observerClient.status == .connected ? .green : .gray)
          .frame(width: 6, height: 6)
        Text(observerClient.status == .connected ? "Live" : "Offline")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer()

      if !manager.isInitialLoading {
        LastUpdatedView(lastUpdatedText: manager.lastUpdatedText)
      }
    }

    // Loading State
    if manager.isInitialLoading {
      loadingState
    }
    // Error State
    else if let error = manager.lastError {
      errorState(error: error)
    }
    // Empty State
    else if manager.apiKeys.isEmpty {
      emptyState
    }
    // Content
    else {
      // Usage Instructions Card
      usageInstructionsCard

      // API Keys List
      apiKeysSection
    }
  }

  // MARK: - Usage Instructions Card

  private var usageInstructionsCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Label("Quick Start", systemImage: "info.circle.fill")
          .font(.headline)
          .foregroundStyle(.blue)
        Spacer()
      }

      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Text("Model")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(width: 80, alignment: .leading)
          Text("apple-intelligence")
            .font(.system(.subheadline, design: .monospaced))
          Spacer()
          copyButton(text: "apple-intelligence")
        }

        HStack {
          Text("Endpoint")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(width: 80, alignment: .leading)
          Text(Config.apiBaseURL)
            .font(.system(.caption, design: .monospaced))
            .lineLimit(1)
          Spacer()
          copyButton(text: Config.apiBaseURL)
        }
      }
    }
    .padding(Constants.standardPadding)
    .glassEffect(in: .rect(cornerRadius: Constants.cornerRadius, style: .continuous))
  }

  // MARK: - API Keys Section

  private var apiKeysSection: some View {
    VStack(alignment: .leading, spacing: Constants.summaryCardSpacing) {
      Text("Your API Keys")
        .font(.headline)
        .foregroundStyle(.secondary)

      ForEach(manager.apiKeys) { key in
        APIKeyCard(
          key: key,
          isVisible: visibleKeys.contains(key.key),
          isEditing: editingKey == key.key,
          isCopied: copiedText == key.key,
          editingName: $editingName,
          onToggleVisibility: { toggleKeyVisibility(key.key) },
          onCopy: { copyKey(key.key) },
          onEdit: {
            editingKey = key.key
            editingName = key.name ?? ""
          },
          onSave: { updateKeyName(key) },
          onCancelEdit: {
            editingKey = nil
            editingName = ""
          },
          onDelete: {
            keyToDelete = key
            showDeleteConfirmation = true
          }
        )
      }
    }
  }

  // MARK: - States

  private var loadingState: some View {
    VStack(spacing: 16) {
      ProgressView()
      Text("Loading API keys...")
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 60)
  }

  private var emptyState: some View {
    VStack(spacing: 16) {
      Image(systemName: "key.fill")
        .font(.system(size: 48))
        .foregroundStyle(.secondary)

      Text("No API Keys")
        .font(.title2)
        .fontWeight(.semibold)

      Text("Create an API key to get started")
        .font(.subheadline)
        .foregroundStyle(.secondary)

      Button("Create API Key") {
        createKey()
      }
      .buttonStyle(.borderedProminent)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 60)
  }

  private func errorState(error: String) -> some View {
    HStack {
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(.orange)

      Text(error)
        .font(.subheadline)

      Spacer()

      Button("Retry") {
        Task {
          guard let token = authManager.authToken else { return }
          await manager.loadAPIKeys(authToken: token)
        }
      }
      .buttonStyle(.glass)
    }
    .padding()
    .glassEffect(in: .rect(cornerRadius: 12, style: .continuous))
  }

  // MARK: - Helpers

  private func copyButton(text: String) -> some View {
    Button {
      copyToClipboard(text)
    } label: {
      HStack(spacing: 4) {
        Image(systemName: copiedText == text ? "checkmark" : "doc.on.doc")
          .font(.caption)
          .foregroundStyle(copiedText == text ? .green : .blue)
        if copiedText == text {
          Text("Copied")
            .font(.caption2)
            .foregroundStyle(.green)
        }
      }
      .animation(.easeInOut(duration: 0.2), value: copiedText)
    }
    .buttonStyle(.plain)
  }

  private func createKey() {
    Task {
      guard let token = authManager.authToken else { return }
      let defaultName = ISO8601DateFormatter().string(from: Date())
      await manager.createAPIKey(name: defaultName, authToken: token)
    }
  }

  private func updateKeyName(_ key: APIKey) {
    Task {
      guard let token = authManager.authToken else { return }
      await manager.updateAPIKey(key: key.key, name: editingName, authToken: token)
      editingKey = nil
      editingName = ""
    }
  }

  private func copyKey(_ key: String) {
    copyToClipboard(key)
  }

  private func copyToClipboard(_ text: String) {
    #if os(macOS)
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(text, forType: .string)
    #else
      UIPasteboard.general.string = text
    #endif

    // Show feedback
    copiedText = text
    Task {
      try? await Task.sleep(for: .seconds(2))
      if copiedText == text {
        copiedText = nil
      }
    }
  }

  private func toggleKeyVisibility(_ key: String) {
    if visibleKeys.contains(key) {
      visibleKeys.remove(key)
    } else {
      visibleKeys.insert(key)
    }
  }

  private func maskKey(_ key: String) -> String {
    guard key.count > maskMinLength else { return key }
    return "\(key.prefix(maskPrefixLength))...\(key.suffix(maskSuffixLength))"
  }
}

// MARK: - API Key Card

private struct APIKeyCard: View {
  let key: APIKey
  let isVisible: Bool
  let isEditing: Bool
  let isCopied: Bool
  @Binding var editingName: String
  let onToggleVisibility: () -> Void
  let onCopy: () -> Void
  let onEdit: () -> Void
  let onSave: () -> Void
  let onCancelEdit: () -> Void
  let onDelete: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      // Header: Name + Actions
      HStack {
        if isEditing {
          TextField("Name", text: $editingName)
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 200)
          Button("Save") { onSave() }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
          Button("Cancel") { onCancelEdit() }
            .controlSize(.small)
        } else {
          Text(key.name ?? "Unnamed")
            .font(.headline)
          Button { onEdit() } label: {
            Image(systemName: "pencil")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          .buttonStyle(.plain)
        }

        Spacer()

        HStack(spacing: 16) {
          Button { onCopy() } label: {
            HStack(spacing: 4) {
              Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                .foregroundStyle(isCopied ? .green : .blue)
              if isCopied {
                Text("Copied")
                  .font(.caption2)
                  .foregroundStyle(.green)
              }
            }
            .animation(.easeInOut(duration: 0.2), value: isCopied)
          }
          .buttonStyle(.plain)

          Button { onDelete() } label: {
            Image(systemName: "trash")
              .foregroundStyle(.red)
          }
          .buttonStyle(.plain)
        }
      }

      // Key Value
      HStack {
        Text(isVisible ? key.key : maskedKey)
          .font(.system(.caption, design: .monospaced))
          .foregroundStyle(.secondary)
          .textSelection(.enabled)
          .lineLimit(1)

        Spacer()

        Button { onToggleVisibility() } label: {
          Image(systemName: isVisible ? "eye.slash" : "eye")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
      }

      // Timestamps
      HStack {
        Text("Created: \(formatDate(key.created_at))")
          .font(.caption)
          .foregroundStyle(.secondary)

        Spacer()

        if let lastUsed = key.last_used_at {
          Text("Last used: \(formatRelativeTime(lastUsed))")
            .font(.caption)
            .foregroundStyle(.secondary)
        } else {
          Text("Never used")
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
      }
    }
    .padding(12)
    .glassEffect(in: .rect(cornerRadius: 12, style: .continuous))
  }

  private var maskedKey: String {
    guard key.key.count > 24 else { return key.key }
    return "\(key.key.prefix(20))...\(key.key.suffix(4))"
  }

  private func formatDate(_ timestamp: Int) -> String {
    let date = Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000)
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter.string(from: date)
  }

  private func formatRelativeTime(_ timestamp: Int) -> String {
    let date = Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000)
    let diff = Date().timeIntervalSince(date)
    let seconds = Int(diff)
    let minutes = seconds / 60
    let hours = minutes / 60
    let days = hours / 24

    if days > 0 { return "\(days)d ago" }
    if hours > 0 { return "\(hours)h ago" }
    if minutes > 0 { return "\(minutes)m ago" }
    return "\(seconds)s ago"
  }
}

#Preview {
  APIKeysView()
    .environment(AuthManager())
    .environment(ObserverClient())
}
