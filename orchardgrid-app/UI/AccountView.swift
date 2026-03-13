import ClerkKit
#if os(iOS)
  import ClerkKitUI
#endif
import SwiftUI

struct AccountView: View {
  @Environment(AuthManager.self) private var authManager
  @State private var showDeleteConfirmation = false
  @State private var showFinalConfirmation = false
  @State private var isDeleting = false

  var body: some View {
    Group {
      if authManager.isAuthenticated {
        authenticatedContent
      } else {
        guestContent
      }
    }
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
        Task { await deleteAccount() }
      }
    } message: {
      Text("This action cannot be undone. All your devices, API keys, and tasks will be deleted.")
    }
  }

  // MARK: - Guest Content

  private var guestContent: some View {
    ScrollView {
      VStack(spacing: 24) {
        GuestFeaturePrompt(
          icon: "person.circle",
          title: "Sign In to Your Account",
          description: "Sign in to unlock all features and track your contributions across devices.",
          benefits: [
            "Manage your profile",
            "Track all your devices",
            "Access API keys and logs",
          ],
          buttonTitle: "Sign In"
        )

        OpenSourceCard()
      }
      .padding()
    }
  }

  // MARK: - Authenticated Content

  private var authenticatedContent: some View {
    Form {
      Section("Profile") {
        HStack {
          #if os(iOS)
            UserButton()
              .frame(width: 36, height: 36)
          #endif

          if let user = Clerk.shared.user {
            let displayName = [user.firstName, user.lastName]
              .compactMap { $0 }.joined(separator: " ")

            VStack(alignment: .leading, spacing: 2) {
              Text(displayName.isEmpty ? "User" : displayName)
                .font(.headline)
              if let email = user.primaryEmailAddress?.emailAddress {
                Text(email)
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            }
          }

          Spacer()
        }
        .padding(.vertical, 4)
      }

      Section("Open Source") {
        OpenSourceCard(style: .form)
      }

      Section("Session") {
        Button("Sign Out", role: .destructive) {
          Task { await authManager.signOut() }
        }
      }

      Section {
        Button("Delete Account", role: .destructive) {
          showDeleteConfirmation = true
        }
        .disabled(isDeleting)
      } footer: {
        Text(
          "This will permanently delete your account and all associated data including devices, API keys, and tasks. This action cannot be undone."
        )
        .font(.caption)
      }
    }
    .formStyle(.grouped)
  }

  private func deleteAccount() async {
    guard let token = await authManager.getToken() else { return }

    isDeleting = true
    defer { isDeleting = false }

    do {
      let url = URL(string: "\(Config.apiBaseURL)/account")!
      var request = URLRequest(url: url)
      request.httpMethod = "DELETE"
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

      let (data, response) = try await Config.urlSession.data(for: request)

      guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
        let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
        throw NSError(domain: errorText, code: -1)
      }

      await authManager.signOut()
      Logger.log(.auth, "Account deleted successfully")
    } catch {
      Logger.error(.auth, "Failed to delete account: \(error.localizedDescription)")
    }
  }
}

// MARK: - Open Source Card

struct OpenSourceCard: View {
  enum Style { case standalone, form }

  var style: Style = .standalone

  private let repoURL = URL(string: "https://github.com/BingoWon/orchardgrid-app")!

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      if style == .standalone {
        Text("Open Source")
          .font(.headline)
      }

      Text("The OrchardGrid app is open source. Explore and contribute on GitHub.")
        .font(.subheadline)
        .foregroundStyle(.secondary)

      HStack(spacing: 12) {
        Image("GitHubLogo")
          .resizable()
          .scaledToFit()
          .frame(width: 24, height: 24)

        Text(repoURL.absoluteString)
          .font(.subheadline)
          .foregroundStyle(.primary)
          .textSelection(.enabled)

        Spacer()

        Link("Open", destination: repoURL)
          .buttonStyle(.borderedProminent)
      }
    }
    .modifier(OpenSourceCardStyle(style: style))
  }
}

private struct OpenSourceCardStyle: ViewModifier {
  let style: OpenSourceCard.Style

  func body(content: Content) -> some View {
    switch style {
    case .standalone:
      content
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(in: .rect(cornerRadius: 12, style: .continuous))
    case .form:
      content
        .padding(.vertical, 4)
    }
  }
}

#Preview {
  AccountView()
    .environment(AuthManager())
}
