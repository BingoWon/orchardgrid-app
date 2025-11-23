import SwiftUI

struct AccountView: View {
  @Environment(AuthManager.self) private var authManager
  @State private var showDeleteConfirmation = false
  @State private var showFinalConfirmation = false
  @State private var isDeleting = false

  private let repoURL = URL(string: "https://github.com/BingoWon/orchardgrid-app")!

  var body: some View {
    Form(content: {
      Section("Profile") {
        if let user = authManager.currentUser {
          LabeledContent("Name", value: user.name ?? "N/A")
          LabeledContent("Email", value: user.email)
        }
      }

      Section("Open Source") {
        VStack(alignment: .leading, spacing: 12) {
          Text("The OrchardGrid app is open source. You can read the code, build it yourself, and contribute improvements.")
            .font(.subheadline)
            .foregroundStyle(.secondary)

          HStack(spacing: 12) {
            Image(systemName: "link")
              .font(.title3)
              .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: 4) {
              Text("GitHub Repository")
                .font(.headline)
              Text(repoURL.absoluteString)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            }

            Spacer()

            Link(destination: repoURL) {
              Label("Open", systemImage: "arrow.up.right")
            }
            .buttonStyle(.borderedProminent)
          }
        }
        .padding(.vertical, 4)
      }

      Section("Session") {
        Button("Sign Out", role: .destructive) {
          authManager.logout()
        }
      }

      Section {
        Button("Delete Account", role: .destructive) {
          showDeleteConfirmation = true
        }
        .disabled(isDeleting)
      } footer: {
        Text("This will permanently delete your account and all associated data including devices, API keys, and tasks. This action cannot be undone.")
          .font(.caption)
      }
    })
    .formStyle(.grouped)
    .navigationTitle("Account")
    .toolbarRole(.editor)
    .toolbarTitleDisplayMode(.inlineLarge)
    .alert("Delete Account?", isPresented: $showDeleteConfirmation) {
      Button("Cancel", role: .cancel) {}
      Button("Continue", role: .destructive) {
        showFinalConfirmation = true
      }
    } message: {
      Text("This will permanently delete your account and all associated data.")
    }
    .alert("Are you absolutely sure?", isPresented: $showFinalConfirmation) {
      Button("Cancel", role: .cancel) {}
      Button("Delete Account", role: .destructive) {
        Task {
          await deleteAccount()
        }
      }
    } message: {
      Text("This action cannot be undone. All your devices, API keys, and tasks will be deleted.")
    }
  }

  private func deleteAccount() async {
    guard let token = authManager.authToken else { return }

    isDeleting = true
    defer { isDeleting = false }

    do {
      let url = URL(string: "\(Config.apiBaseURL)/auth/account")!
      var request = URLRequest(url: url)
      request.httpMethod = "DELETE"
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

      let (data, response) = try await URLSession.shared.data(for: request)

      guard let httpResponse = response as? HTTPURLResponse else {
        throw NSError(domain: "Invalid response", code: -1)
      }

      guard httpResponse.statusCode == 200 else {
        let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
        throw NSError(domain: errorText, code: httpResponse.statusCode)
      }

      // Account deleted successfully, logout
      await MainActor.run {
        authManager.logout()
      }

      Logger.log(.auth, "Account deleted successfully")
    } catch {
      Logger.error(.auth, "Failed to delete account: \(error.localizedDescription)")
    }
    }
}

#Preview {
  AccountView()
    .environment(AuthManager())
}
