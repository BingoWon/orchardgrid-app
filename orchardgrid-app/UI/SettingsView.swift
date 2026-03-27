import ClerkKit
import SwiftUI

#if os(iOS)
  import ClerkKitUI
#endif

struct SettingsView: View {
  @Environment(AuthManager.self) private var authManager
  @State private var showDeleteConfirmation = false
  @State private var showFinalConfirmation = false
  @State private var isDeleting = false
  @AppStorage("AppLanguage") private var appLanguage = "system"
  @State private var showRestartAlert = false

  private let repoURL = URL(string: "https://github.com/BingoWon/orchardgrid-app")!

  var body: some View {
    ScrollView {
      GlassEffectContainer(spacing: Constants.standardSpacing) {
        VStack(alignment: .leading, spacing: Constants.standardSpacing) {
          if authManager.isAuthenticated {
            profileCard
          }

          languageSection
          sourceCodeRow

          if authManager.isAuthenticated {
            signOutButton
            deleteAccountButton
          } else {
            GuestFeaturePrompt(
              icon: "person.circle",
              title: "Sign In to Unlock All Features",
              description:
                "Sign in to track your contributions across devices and access all settings.",
              benefits: [
                "Manage your profile",
                "Track all your devices",
                "Access API keys and logs",
              ],
              buttonTitle: "Sign In"
            )
          }
        }
        .padding(Constants.standardPadding)
      }
    }
    .navigationTitle(String(localized: "Settings"))
    .toolbarRole(.editor)
    .toolbarTitleDisplayMode(.inlineLarge)
    .alert(String(localized: "Delete Account?"), isPresented: $showDeleteConfirmation) {
      Button(String(localized: "Cancel"), role: .cancel) {}
      Button(String(localized: "Continue"), role: .destructive) {
        showFinalConfirmation = true
      }
    } message: {
      Text("This will permanently delete your account and all associated data.")
    }
    .alert(String(localized: "Are you absolutely sure?"), isPresented: $showFinalConfirmation) {
      Button(String(localized: "Cancel"), role: .cancel) {}
      Button(String(localized: "Delete Account"), role: .destructive) {
        Task { await deleteAccount() }
      }
    } message: {
      Text(
        "This action cannot be undone. All your devices, API keys, and tasks will be deleted."
      )
    }
    .alert(String(localized: "Restart Required"), isPresented: $showRestartAlert) {
      Button("OK") {}
    } message: {
      Text("Please restart the app to apply the language change.")
    }
  }

  // MARK: - Language

  private var languageSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      Label(String(localized: "Language"), systemImage: "globe")
        .font(.subheadline.weight(.medium))

      Picker(String(localized: "Language"), selection: $appLanguage) {
        Text(String(localized: "System Default")).tag("system")
        Text("English").tag("en")
        Text("中文").tag("zh-Hans")
      }
      .pickerStyle(.segmented)
      .onChange(of: appLanguage) {
        if appLanguage == "system" {
          UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
          UserDefaults.standard.set([appLanguage], forKey: "AppleLanguages")
        }
        showRestartAlert = true
      }
    }
    .padding(Constants.standardPadding)
    .glassEffect(in: .rect(cornerRadius: Constants.cornerRadius, style: .continuous))
  }

  // MARK: - Profile Card

  private var profileCard: some View {
    HStack(spacing: 12) {
      #if os(iOS)
        UserButton()
          .frame(width: 40, height: 40)
      #endif

      if let user = Clerk.shared.user {
        let displayName =
          [user.firstName, user.lastName]
          .compactMap { $0 }
          .joined(separator: " ")

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
    .padding(Constants.standardPadding)
    .glassEffect(in: .rect(cornerRadius: Constants.cornerRadius, style: .continuous))
  }

  // MARK: - Source Code

  private var sourceCodeRow: some View {
    Link(destination: repoURL) {
      HStack(spacing: 12) {
        Image("GitHubLogo")
          .resizable()
          .scaledToFit()
          .frame(width: 20, height: 20)

        VStack(alignment: .leading, spacing: 2) {
          Text(String(localized: "Source Code"))
            .font(.subheadline.weight(.medium))
          Text("BingoWon/orchardgrid-app")
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Spacer()

        Image(systemName: "arrow.up.right")
          .font(.caption2.weight(.semibold))
          .foregroundStyle(.tertiary)
      }
      .padding(Constants.standardPadding)
      .glassEffect(in: .rect(cornerRadius: Constants.cornerRadius, style: .continuous))
    }
    .buttonStyle(.plain)
  }

  // MARK: - Actions

  private var signOutButton: some View {
    Button {
      Task { await authManager.signOut() }
    } label: {
      Text(String(localized: "Sign Out"))
        .font(.subheadline)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }
    .buttonStyle(.glass)
  }

  private var deleteAccountButton: some View {
    VStack(spacing: 8) {
      Button(role: .destructive) {
        showDeleteConfirmation = true
      } label: {
        Text(String(localized: "Delete Account"))
          .font(.caption)
      }
      .buttonStyle(.plain)
      .foregroundStyle(.red.opacity(0.6))
      .disabled(isDeleting)

      Text("Permanently removes your account, devices, API keys, and all tasks.")
        .font(.caption2)
        .foregroundStyle(.quaternary)
        .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity)
    .padding(.top, 8)
  }

  private func deleteAccount() async {
    isDeleting = true
    defer { isDeleting = false }
    do {
      try await authManager.deleteAccount()
    } catch {
      Logger.error(.auth, "Failed to delete account: \(error.localizedDescription)")
    }
  }
}

#Preview {
  SettingsView()
    .environment(AuthManager())
}
