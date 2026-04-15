import SwiftUI

struct APIKeysView: View {
  @Environment(AuthManager.self) private var authManager
  @Environment(ObserverClient.self) private var observerClient
  @Environment(APIKeysManager.self) private var manager
  @State private var editingHint: String?
  @State private var editingName = ""
  @State private var showDeleteConfirmation = false
  @State private var keyToDelete: APIKey?
  @State private var showAPIReference = true
  @State private var newlyCreatedKey: String?

  private var docsURL: URL {
    URL(string: "\(Config.hostURL)/docs")!
  }

  var body: some View {
    Group {
      if !authManager.isAuthenticated {
        guestContent
      } else if !manager.isInitialLoading, manager.apiKeys.isEmpty, manager.lastError == nil {
        emptyState
      } else {
        keysContent
      }
    }
    .navigationTitle(String(localized: "API Keys"))
    .toolbarRole(.editor)
    .toolbarTitleDisplayMode(.inlineLarge)
    .contentToolbar {
      if authManager.isAuthenticated, !manager.apiKeys.isEmpty {
        HStack(spacing: 12) {
          if manager.isRefreshing {
            ProgressView()
              .controlSize(.small)
          }

          Button {
            createKey()
          } label: {
            Label(String(localized: "Create"), systemImage: "plus")
          }
        }
      }
    }
    .task(id: authManager.userId) {
      await manager.loadAPIKeys()
    }
    .alert(String(localized: "Delete API Key?"), isPresented: $showDeleteConfirmation) {
      Button(String(localized: "Cancel"), role: .cancel) {}
      Button(String(localized: "Delete"), role: .destructive) {
        if let key = keyToDelete {
          Task { await manager.deleteAPIKey(hint: key.keyHint) }
        }
      }
    } message: {
      if let key = keyToDelete {
        Text(
          "Are you sure you want to delete \"\(key.name ?? String(localized: "this API key"))\"?"
        )
      }
    }
    .alert(
      String(localized: "API Key Created"),
      isPresented: .init(
        get: { newlyCreatedKey != nil },
        set: { if !$0 { newlyCreatedKey = nil } }
      )
    ) {
      Button(String(localized: "Copy Key")) {
        if let key = newlyCreatedKey { Clipboard.copy(key) }
        newlyCreatedKey = nil
      }
      Button(String(localized: "Done")) {
        newlyCreatedKey = nil
      }
    } message: {
      if let key = newlyCreatedKey {
        Text("Save this key now — it won't be shown again:\n\n\(key)")
      }
    }
  }

  // MARK: - Guest Content

  private var guestContent: some View {
    ScrollView {
      GlassEffectContainer(spacing: Constants.standardSpacing) {
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
        .padding(Constants.standardPadding)
      }
    }
  }

  // MARK: - Keys Content

  private var keysContent: some View {
    ScrollView {
      GlassEffectContainer(spacing: Constants.standardSpacing) {
        VStack(alignment: .leading, spacing: Constants.standardSpacing) {
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
            ErrorBanner(error: error) {
              Task { await manager.loadAPIKeys() }
            }
          } else {
            apiReferenceCard
            apiKeysSection
          }
        }
        .padding(Constants.standardPadding)
      }
    }
    .refreshable {
      await manager.loadAPIKeys(isManualRefresh: true)
    }
  }

  // MARK: - API Reference Card

  private var apiReferenceCard: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button {
        withAnimation(.easeInOut(duration: 0.2)) { showAPIReference.toggle() }
      } label: {
        HStack {
          Label(String(localized: "API Reference"), systemImage: "book")
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
            model: "apple-foundationmodel",
            fields: [
              ("messages", "array", "[{role, content}]"),
              ("stream", "bool?", "false — set true for SSE"),
            ]
          )

          Divider()

          endpointSection(
            method: "POST",
            path: "/v1/images/generations",
            model: "apple-foundationmodel-image",
            fields: [
              ("prompt", "string", "Text description"),
              ("n", "int?", "1 — number of images"),
              ("style", "string?", "illustration | sketch"),
            ]
          )

          Divider()

          Link(destination: docsURL) {
            HStack {
              Image(systemName: "doc.text")
              Text(String(localized: "View Full Documentation"))
              Spacer()
              Image(systemName: "arrow.up.right")
                .font(.caption)
            }
            .font(.subheadline)
            .foregroundStyle(.blue)
          }
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
      Text(String(localized: "Your API Keys"))
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
    VStack(spacing: 24) {
      Image(systemName: "key.fill")
        .font(.system(size: 52))
        .foregroundStyle(.secondary)

      VStack(spacing: 6) {
        Text(String(localized: "No API Keys"))
          .font(.title3.weight(.semibold))
        Text(String(localized: "Create an API key to get started"))
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }

      Button {
        createKey()
      } label: {
        Label(String(localized: "Create API Key"), systemImage: "plus")
          .frame(minWidth: 160)
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.large)
      .padding(.top, 4)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  // MARK: - Helpers

  private static let nameFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd HH:mm"
    f.timeZone = TimeZone.current
    return f
  }()

  private func createKey() {
    Task {
      let defaultName = Self.nameFormatter.string(from: Date())
      if let created = await manager.createAPIKey(name: defaultName),
        let fullKey = created.key
      {
        newlyCreatedKey = fullKey
      }
    }
  }

  private func updateKeyName(_ key: APIKey) {
    Task {
      await manager.updateAPIKey(hint: key.keyHint, name: editingName)
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
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        if isEditing {
          TextField(String(localized: "Name"), text: $editingName)
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 200)
          Button(String(localized: "Save")) { onSave() }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
          Button(String(localized: "Cancel")) { onCancelEdit() }
            .controlSize(.small)
        } else {
          Text(key.name ?? String(localized: "Unnamed"))
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

        HStack(spacing: 12) {
          CopyButton(text: key.keyHint)

          ShareLink(item: key.keyHint) {
            Image(systemName: "square.and.arrow.up")
              .font(.caption)
              .foregroundStyle(.blue)
          }
          .buttonStyle(.plain)

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
          String(
            localized:
              "Created: \(key.createdDate.formatted(date: .abbreviated, time: .shortened))"
          )
        )
        .font(.caption)
        .foregroundStyle(.secondary)

        Spacer()

        if let lastUsedDate = key.lastUsedDate {
          Text(
            String(
              localized:
                "Last used: \(lastUsedDate.formatted(.relative(presentation: .named)))"
            )
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        } else {
          Text(String(localized: "Never used"))
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
      }
    }
    .padding(12)
    .background(.ultraThinMaterial, in: .rect(cornerRadius: 12, style: .continuous))
  }
}

#Preview {
  APIKeysView()
    .environment(AuthManager(api: .preview))
    .environment(APIKeysManager(api: .preview))
    .environment(ObserverClient())
}
