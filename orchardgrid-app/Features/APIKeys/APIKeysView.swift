import SwiftUI

struct APIKeysView: View {
  @Environment(AuthManager.self) private var authManager
  @Environment(ObserverClient.self) private var observerClient
  @State private var manager = APIKeysManager()
  @State private var editingHint: String?
  @State private var editingName = ""
  @State private var showDeleteConfirmation = false
  @State private var keyToDelete: APIKey?
  @State private var showAPIReference = true
  @State private var newlyCreatedKey: String?

  var body: some View {
    ScrollView {
      GlassEffectContainer(spacing: Constants.standardSpacing) {
        VStack(alignment: .leading, spacing: Constants.standardSpacing) {
          if authManager.isAuthenticated {
            authenticatedContent
          } else {
            GuestFeaturePrompt(
              icon: "key.fill",
              title: "Get Your API Keys",
              description:
                "Sign in to create API keys and access OrchardGrid from your applications.",
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
      guard let token = await authManager.getToken() else { return }
      await manager.loadAPIKeys(authToken: token, isManualRefresh: true)
    }
    .navigationTitle("API Keys")
    .navigationSubtitle(manager.apiKeys.isEmpty ? "" : "\(manager.apiKeys.count) keys")
    .toolbarRole(.editor)
    .toolbarTitleDisplayMode(.inlineLarge)
    .contentToolbar {
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
        }
      }
    }
    .task(id: authManager.userId) {
      guard let token = await authManager.getToken() else { return }
      await manager.loadAPIKeys(authToken: token)
    }
    .alert("Delete API Key?", isPresented: $showDeleteConfirmation) {
      Button("Cancel", role: .cancel) {}
      Button("Delete", role: .destructive) {
        if let key = keyToDelete {
          Task {
            guard let token = await authManager.getToken() else { return }
            await manager.deleteAPIKey(hint: key.keyHint, authToken: token)
          }
        }
      }
    } message: {
      if let key = keyToDelete {
        Text("Are you sure you want to delete \"\(key.name ?? "this API key")\"?")
      }
    }
    .alert(
      "API Key Created",
      isPresented: .init(
        get: { newlyCreatedKey != nil },
        set: { if !$0 { newlyCreatedKey = nil } }
      )
    ) {
      Button("Copy Key") {
        if let key = newlyCreatedKey { Clipboard.copy(key) }
        newlyCreatedKey = nil
      }
      Button("Done") {
        newlyCreatedKey = nil
      }
    } message: {
      if let key = newlyCreatedKey {
        Text("Save this key now — it won't be shown again:\n\n\(key)")
      }
    }
  }

  // MARK: - Authenticated Content

  @ViewBuilder
  private var authenticatedContent: some View {
    HStack {
      ConnectionStatusBadge(isConnected: observerClient.status == .connected)
      Spacer()
      if !manager.isInitialLoading {
        LastUpdatedView(lastUpdatedText: manager.lastUpdatedText)
      }
    }

    if manager.isInitialLoading {
      ProgressView()
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    } else if let error = manager.lastError {
      ErrorBanner(message: error) {
        Task {
          guard let token = await authManager.getToken() else { return }
          await manager.loadAPIKeys(authToken: token)
        }
      }
    } else if manager.apiKeys.isEmpty {
      emptyState
    } else {
      apiReferenceCard
      apiKeysSection
    }
  }

  // MARK: - API Reference Card

  private var apiReferenceCard: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button {
        withAnimation(.easeInOut(duration: 0.2)) { showAPIReference.toggle() }
      } label: {
        HStack {
          Label("API Reference", systemImage: "book")
            .font(.subheadline.weight(.semibold))
          Spacer()
          Image(systemName: "chevron.down")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.tertiary)
            .rotationEffect(.degrees(showAPIReference ? 0 : -90))
        }
        .foregroundStyle(.primary)
        .padding(Constants.standardPadding)
      }
      .buttonStyle(.plain)

      if showAPIReference {
        VStack(alignment: .leading, spacing: 16) {
          HStack {
            Text(Config.hostURL)
              .font(.system(.callout, design: .monospaced))
              .lineLimit(1)
            Spacer()
            CopyButton(text: Config.hostURL)
          }
          .padding(10)
          .background(.fill.quaternary, in: .rect(cornerRadius: 8))

          endpointSection(
            method: "POST",
            path: "/v1/chat/completions",
            model: "apple-intelligence",
            fields: [
              ("messages", "array", "[{role, content}]"),
              ("stream", "bool?", "false — set true for SSE"),
            ]
          )

          Divider()

          endpointSection(
            method: "POST",
            path: "/v1/images/generations",
            model: "apple-intelligence-image",
            fields: [
              ("prompt", "string", "Text description"),
              ("n", "int?", "1 — number of images"),
              ("style", "string?", "illustration | sketch"),
            ]
          )
        }
        .padding([.horizontal, .bottom], Constants.standardPadding)
      }
    }
    .glassEffect(in: .rect(cornerRadius: Constants.cornerRadius, style: .continuous))
  }

  private func endpointSection(
    method: String,
    path: String,
    model: String,
    fields: [(name: String, type: String, desc: String)]
  ) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 6) {
        Text(method)
          .font(.system(.caption2, design: .monospaced, weight: .bold))
          .padding(.horizontal, 6)
          .padding(.vertical, 2)
          .background(.green.opacity(0.15), in: .rect(cornerRadius: 4))
          .foregroundStyle(.green)
        Text(path)
          .font(.system(.subheadline, design: .monospaced))
      }

      HStack(spacing: 6) {
        Text("Model")
          .font(.caption2)
          .foregroundStyle(.secondary)
        Text(model)
          .font(.system(.caption2, design: .monospaced))
          .padding(.horizontal, 6)
          .padding(.vertical, 2)
          .background(.blue.opacity(0.12), in: .capsule)
          .foregroundStyle(.blue)
        CopyButton(text: model)
      }

      VStack(spacing: 4) {
        ForEach(fields, id: \.name) { field in
          HStack(alignment: .top, spacing: 0) {
            Text(field.name)
              .font(.system(.caption, design: .monospaced))
              .frame(width: 72, alignment: .leading)
            Text(field.type)
              .font(.caption2)
              .foregroundStyle(.secondary)
              .frame(width: 52, alignment: .leading)
            Text(field.desc)
              .font(.caption2)
              .foregroundStyle(.tertiary)
            Spacer()
          }
        }
      }
    }
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
          isEditing: editingHint == key.keyHint,
          editingName: $editingName,
          onEdit: {
            editingHint = key.keyHint
            editingName = key.name ?? ""
          },
          onSave: { updateKeyName(key) },
          onCancelEdit: {
            editingHint = nil
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

  private var emptyState: some View {
    ContentUnavailableView {
      Label("No API Keys", systemImage: "key.fill")
    } description: {
      Text("Create an API key to get started")
    } actions: {
      Button("Create API Key") { createKey() }
        .buttonStyle(.borderedProminent)
    }
    .frame(maxWidth: .infinity)
  }

  // MARK: - Helpers

  private func createKey() {
    Task {
      guard let token = await authManager.getToken() else { return }
      let defaultName = ISO8601DateFormatter().string(from: Date())
      if let created = await manager.createAPIKey(name: defaultName, authToken: token),
        let fullKey = created.key
      {
        newlyCreatedKey = fullKey
      }
    }
  }

  private func updateKeyName(_ key: APIKey) {
    Task {
      guard let token = await authManager.getToken() else { return }
      await manager.updateAPIKey(hint: key.keyHint, name: editingName, authToken: token)
      editingHint = nil
      editingName = ""
    }
  }

}

// MARK: - API Key Card

private struct APIKeyCard: View {
  let key: APIKey
  let isEditing: Bool
  @Binding var editingName: String
  let onEdit: () -> Void
  let onSave: () -> Void
  let onCancelEdit: () -> Void
  let onDelete: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
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
          Button {
            onEdit()
          } label: {
            Image(systemName: "pencil")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          .buttonStyle(.plain)
        }

        Spacer()

        HStack(spacing: 16) {
          CopyButton(text: key.keyHint)

          Button {
            onDelete()
          } label: {
            Image(systemName: "trash")
              .foregroundStyle(.red)
          }
          .buttonStyle(.plain)
        }
      }

      Text(key.keyHint)
        .font(.system(.caption, design: .monospaced))
        .foregroundStyle(.secondary)
        .textSelection(.enabled)
        .lineLimit(1)

      HStack {
        Text(
          "Created: \(timestampDate(key.createdAt).formatted(date: .abbreviated, time: .shortened))"
        )
        .font(.caption)
        .foregroundStyle(.secondary)

        Spacer()

        if let lastUsed = key.lastUsedAt {
          Text("Last used: \(timestampDate(lastUsed).formatted(.relative(presentation: .named)))")
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

  private func timestampDate(_ ms: Int) -> Date {
    Date(timeIntervalSince1970: TimeInterval(ms) / 1000)
  }
}

#Preview {
  APIKeysView()
    .environment(AuthManager())
    .environment(ObserverClient())
}
