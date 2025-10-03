import AppKit
import SwiftUI

struct APIKeysView: View {
  @Environment(AuthManager.self) private var authManager
  @State private var manager = APIKeysManager()
  @State private var showCreateSheet = false
  @State private var newKeyName = ""
  @State private var createdKey: APIKey?
  @State private var showKeyAlert = false

  var body: some View {
    VStack(spacing: 0) {
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
            showCreateSheet = true
          }
          .buttonStyle(.borderedProminent)
        }
      } else {
        List {
          ForEach(manager.apiKeys) { key in
            VStack(alignment: .leading, spacing: 8) {
              HStack {
                Text(key.name ?? "Unnamed")
                  .font(.headline)
                Spacer()
                Button {
                  deleteKey(key)
                } label: {
                  Image(systemName: "trash")
                    .foregroundColor(.red)
                }
                .buttonStyle(.plain)
              }

              Text(key.key)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
                .textSelection(.enabled)

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
    .navigationTitle("API Keys")
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button {
          showCreateSheet = true
        } label: {
          Label("Create API Key", systemImage: "plus")
        }
        .disabled(authManager.authToken == nil)
      }
    }
    .sheet(isPresented: $showCreateSheet) {
      CreateAPIKeySheet(
        name: $newKeyName,
        onCreate: {
          Task {
            guard let token = authManager.authToken else { return }
            if let key = await manager.createAPIKey(name: newKeyName, authToken: token) {
              createdKey = key
              showKeyAlert = true
              newKeyName = ""
              showCreateSheet = false
            }
          }
        },
        onCancel: {
          newKeyName = ""
          showCreateSheet = false
        }
      )
    }
    .alert("API Key Created", isPresented: $showKeyAlert) {
      Button("Copy") {
        if let key = createdKey?.key {
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(key, forType: .string)
        }
      }
      Button("Done", role: .cancel) {
        createdKey = nil
      }
    } message: {
      if let key = createdKey {
        Text("Save this key now. You won't be able to see it again!\n\n\(key.key)")
      }
    }
    .task {
      guard let token = authManager.authToken else { return }
      await manager.loadAPIKeys(authToken: token)
    }
  }

  private func deleteKey(_ key: APIKey) {
    let alert = NSAlert()
    alert.messageText = "Delete API Key"
    alert.informativeText = "Are you sure you want to delete \"\(key.name ?? "this API key")\"?"
    alert.alertStyle = .warning
    alert.addButton(withTitle: "Delete")
    alert.addButton(withTitle: "Cancel")

    if alert.runModal() == .alertFirstButtonReturn {
      Task {
        guard let token = authManager.authToken else { return }
        await manager.deleteAPIKey(key: key.key, authToken: token)
      }
    }
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

struct CreateAPIKeySheet: View {
  @Binding var name: String
  let onCreate: () -> Void
  let onCancel: () -> Void

  var body: some View {
    VStack(spacing: 20) {
      Text("Create New API Key")
        .font(.title2)
        .fontWeight(.bold)

      Text("Give your API key a descriptive name")
        .font(.subheadline)
        .foregroundColor(.secondary)

      TextField("Name (required)", text: $name)
        .textFieldStyle(.roundedBorder)
        .onSubmit {
          if !name.isEmpty {
            onCreate()
          }
        }

      HStack {
        Button("Cancel") {
          onCancel()
        }
        .keyboardShortcut(.cancelAction)

        Spacer()

        Button("Create") {
          onCreate()
        }
        .keyboardShortcut(.defaultAction)
        .disabled(name.isEmpty)
      }
    }
    .padding()
    .frame(width: 400)
  }
}

#Preview {
  APIKeysView()
    .environment(AuthManager())
}
