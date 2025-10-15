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
  @State private var manager = APIKeysManager()
  @State private var editingKey: String?
  @State private var editingName = ""
  @State private var visibleKeys: Set<String> = []
  @State private var showAccountSheet = false

  var body: some View {
    VStack(spacing: 0) {
      // Last Updated
      if !manager.isLoading {
        LastUpdatedView(lastUpdatedText: manager.lastUpdatedText)
          .padding(.horizontal)
          .padding(.top, 8)
      }

      if manager.isLoading {
        ProgressView("Loading API keys...")
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if let error = manager.lastError {
        ContentUnavailableView {
          Label("Error", systemImage: "exclamationmark.triangle")
        } description: {
          Text(error)
        } actions: {
          Button("Retry") {
            Task {
              guard let token = authManager.authToken else { return }
              await manager.loadAPIKeys(authToken: token)
            }
          }
        }
      } else if manager.apiKeys.isEmpty {
        ContentUnavailableView {
          Label("No API Keys", systemImage: "key.fill")
        } description: {
          Text("Create an API key to get started")
        } actions: {
          Button("Create API Key") {
            createKey()
          }
          .buttonStyle(.borderedProminent)
        }
      } else {
        List {
          // Usage Instructions Section
          Section {
            UsageInstructionsView()
          }
          .listRowInsets(EdgeInsets())
          .listRowBackground(Color.clear)

          // API Keys Section
          Section {
            ForEach(manager.apiKeys) { key in
              VStack(alignment: .leading, spacing: 8) {
                HStack {
                  if editingKey == key.key {
                    TextField("Name", text: $editingName)
                      .textFieldStyle(.roundedBorder)
                    Button("Save") {
                      updateKeyName(key)
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Cancel") {
                      editingKey = nil
                      editingName = ""
                    }
                  } else {
                    Text(key.name ?? "Unnamed")
                      .font(.headline)
                    Button {
                      editingKey = key.key
                      editingName = key.name ?? ""
                    } label: {
                      Image(systemName: "pencil")
                        .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                  }
                  Spacer()
                  Button {
                    copyKey(key.key)
                  } label: {
                    Image(systemName: "doc.on.doc")
                      .foregroundColor(.blue)
                  }
                  .buttonStyle(.plain)
                  Button {
                    deleteKey(key)
                  } label: {
                    Image(systemName: "trash")
                      .foregroundColor(.red)
                  }
                  .buttonStyle(.plain)
                }

                HStack {
                  Text(visibleKeys.contains(key.key) ? key.key : maskKey(key.key))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
                  Button {
                    toggleKeyVisibility(key.key)
                  } label: {
                    Image(systemName: visibleKeys.contains(key.key) ? "eye.slash" : "eye")
                      .foregroundColor(.secondary)
                  }
                  .buttonStyle(.plain)
                }

                HStack {
                  Text("Created: \(formatDate(key.created_at))")
                    .font(.caption)
                    .foregroundColor(.secondary)

                  Spacer()

                  if let lastUsed = key.last_used_at {
                    Text("Last used: \(formatLastUsed(lastUsed))")
                      .font(.caption)
                      .foregroundColor(.secondary)
                  } else {
                    Text("Never used")
                      .font(.caption)
                      .foregroundColor(.secondary)
                  }
                }
              }
              .padding(.vertical, 4)
            }
          }
        }
      }
    }
    .navigationTitle("API Keys")
    .toolbarRole(.editor)
    .toolbarTitleDisplayMode(.inlineLarge)
    #if os(macOS)
    .withAccountToolbar(showAccountSheet: $showAccountSheet) {
      Button {
        createKey()
      } label: {
        Label("Create API Key", systemImage: "plus")
      }
      .disabled(authManager.authToken == nil)
    }
    #else
    .toolbar {
      if UIDevice.current.userInterfaceIdiom != .phone {
        ToolbarItem {
          Button {
            createKey()
          } label: {
            Label("Create API Key", systemImage: "plus")
          }
          .disabled(authManager.authToken == nil)
        }
        ToolbarSpacer(.flexible)
        ToolbarItemGroup {
          Button {
            showAccountSheet = true
          } label: {
            Label("Account", systemImage: "person.circle")
              .labelStyle(.iconOnly)
          }
        }
      } else {
        ToolbarItem {
          Button {
            createKey()
          } label: {
            Label("Create API Key", systemImage: "plus")
          }
          .disabled(authManager.authToken == nil)
        }
      }
    }
    .sheet(isPresented: $showAccountSheet) {
      NavigationStack {
        AccountView()
          .navigationBarTitleDisplayMode(.inline)
          .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
              Button(role: .close) {
                showAccountSheet = false
              }
            }
          }
      }
      .presentationDetents([.large])
      .presentationDragIndicator(.visible)
    }
    #endif
    .refreshable {
      guard let token = authManager.authToken else { return }
      await manager.loadAPIKeys(authToken: token)
    }
    .task {
      guard let token = authManager.authToken else { return }
      await manager.loadAPIKeys(authToken: token)
      await manager.startAutoRefresh(interval: RefreshConfig.interval, authToken: token)
    }
    .onDisappear {
      manager.stopAutoRefresh()
    }
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
    #if os(macOS)
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(key, forType: .string)
    #else
      UIPasteboard.general.string = key
    #endif
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

  private func deleteKey(_ key: APIKey) {
    #if os(macOS)
      let alert = NSAlert()
      alert.messageText = "Delete API Key"
      alert.informativeText = "Are you sure you want to delete \"\(key.name ?? "this API key")\"?"
      alert.alertStyle = .warning
      alert.addButton(withTitle: "Cancel")
      alert.addButton(withTitle: "Delete")

      if alert.runModal() == .alertSecondButtonReturn {
        Task {
          guard let token = authManager.authToken else { return }
          await manager.deleteAPIKey(key: key.key, authToken: token)
        }
      }
    #else
      // iOS: Use SwiftUI alert (simplified for now)
      Task {
        guard let token = authManager.authToken else { return }
        await manager.deleteAPIKey(key: key.key, authToken: token)
      }
    #endif
  }

  private func formatDate(_ timestamp: Int) -> String {
    let date = Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000)
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter.string(from: date)
  }

  private func formatLastUsed(_ timestamp: Int) -> String {
    let now = Date()
    let date = Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000)
    let diff = now.timeIntervalSince(date)
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

// MARK: - Usage Instructions View

struct UsageInstructionsView: View {
  @State private var isExpanded = false

  var body: some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 12) {
        // Header
        HStack {
          Label("API Usage", systemImage: "info.circle.fill")
            .font(.headline)
            .foregroundStyle(.blue)

          Spacer()

          Button {
            withAnimation {
              isExpanded.toggle()
            }
          } label: {
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
              .foregroundStyle(.secondary)
          }
          .buttonStyle(.plain)
        }

        if isExpanded {
          Divider()

          // Model Name
          VStack(alignment: .leading, spacing: 4) {
            Text("Model")
              .font(.caption)
              .foregroundStyle(.secondary)
            HStack {
              Text("apple-intelligence")
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
              Button {
                copyToClipboard("apple-intelligence")
              } label: {
                Image(systemName: "doc.on.doc")
                  .foregroundStyle(.blue)
              }
              .buttonStyle(.plain)
            }
          }

          Divider()

          // API Endpoint
          VStack(alignment: .leading, spacing: 4) {
            Text("API Endpoint")
              .font(.caption)
              .foregroundStyle(.secondary)
            HStack {
              Text(Config.apiBaseURL)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
              Button {
                copyToClipboard(Config.apiBaseURL)
              } label: {
                Image(systemName: "doc.on.doc")
                  .foregroundStyle(.blue)
              }
              .buttonStyle(.plain)
            }
          }

          Divider()

          // Documentation Link
          Link(destination: URL(string: "https://orchardgrid.com/docs")!) {
            HStack {
              Image(systemName: "book.fill")
              Text("View Full Documentation")
              Spacer()
              Image(systemName: "arrow.up.right")
            }
            .font(.caption)
          }
        }
      }
      .padding()
    }
  }

  private func copyToClipboard(_ text: String) {
    #if os(macOS)
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(text, forType: .string)
    #else
      UIPasteboard.general.string = text
    #endif
  }
}

#Preview {
  APIKeysView()
    .environment(AuthManager())
}
