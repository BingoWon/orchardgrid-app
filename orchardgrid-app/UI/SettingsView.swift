import ClerkKit
import SwiftUI

#if os(iOS)
  import ClerkKitUI
#endif

struct SettingsView: View {
  @Environment(AuthManager.self) private var authManager
  @Environment(SharingManager.self) private var sharing
  @State private var showDeleteConfirmation = false
  @State private var showFinalConfirmation = false
  @State private var isDeleting = false
  @AppStorage("AppLanguage") private var appLanguage = "system"
  @AppStorage("AppAppearance") private var appAppearance = "system"
  @State private var showRestartAlert = false

  private let repoURL = URL(string: "https://github.com/BingoWon/orchardgrid-app")!

  var body: some View {
    ScrollView {
      GlassEffectContainer(spacing: Constants.standardSpacing) {
        VStack(alignment: .leading, spacing: Constants.standardSpacing) {
          // Profile (auth only)
          if authManager.isAuthenticated {
            profileCard
          }

          // Shared Capabilities
          capabilitiesSection

          // Preferences (Appearance + Language)
          preferencesSection

          // About
          sourceCodeRow

          // Auth actions
          if authManager.isAuthenticated {
            signOutButton
            dangerZone
          } else {
            guestPrompt
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

  // MARK: - Shared Capabilities

  private var capabilitiesSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      Label {
        VStack(alignment: .leading, spacing: 2) {
          Text(String(localized: "Shared Capabilities"))
            .font(.subheadline.weight(.medium))
          Text(String(localized: "Choose which AI features this device shares"))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      } icon: {
        Image(systemName: "cpu")
          .foregroundStyle(.primary)
      }

      Divider()

      VStack(spacing: 0) {
        ForEach(Capability.allCases, id: \.self) { capability in
          CapabilityRow(
            capability: capability,
            isEnabled: sharing.isCapabilityEnabled(capability),
            isAvailable: sharing.isCapabilityAvailable(capability),
            unavailabilityReason: sharing.capabilityUnavailabilityReason(capability),
            needsSettingsRedirect: sharing.capabilityNeedsSettingsRedirect(capability)
          ) { enabled in
            sharing.setCapabilityEnabled(capability, enabled: enabled)
          }

          if capability != Capability.allCases.last {
            Divider()
              .padding(.leading, 40)
          }
        }
      }
    }
    .padding(Constants.standardPadding)
    .glassEffect(in: .rect(cornerRadius: Constants.cornerRadius, style: .continuous))
  }

  // MARK: - Preferences

  private var preferencesSection: some View {
    VStack(spacing: 0) {
      // Appearance
      HStack {
        Label(String(localized: "Appearance"), systemImage: "circle.lefthalf.filled")
          .font(.subheadline.weight(.medium))

        Spacer()

        Picker(String(localized: "Appearance"), selection: $appAppearance) {
          Text(String(localized: "System")).tag("system")
          Text(String(localized: "Light")).tag("light")
          Text(String(localized: "Dark")).tag("dark")
        }
        .pickerStyle(.menu)
        .labelsHidden()
      }
      .padding(.vertical, 10)

      Divider()

      // Language
      HStack {
        Label(String(localized: "Language"), systemImage: "globe")
          .font(.subheadline.weight(.medium))

        Spacer()

        Picker(String(localized: "Language"), selection: $appLanguage) {
          Text(String(localized: "System")).tag("system")
          Text("English").tag("en")
          Text("中文").tag("zh-Hans")
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .onChange(of: appLanguage) {
          if appLanguage == "system" {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
          } else {
            UserDefaults.standard.set([appLanguage], forKey: "AppleLanguages")
          }
          showRestartAlert = true
        }
      }
      .padding(.vertical, 10)
    }
    .padding(.horizontal, Constants.standardPadding)
    .padding(.vertical, 4)
    .glassEffect(in: .rect(cornerRadius: Constants.cornerRadius, style: .continuous))
  }

  // MARK: - Profile

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

  // MARK: - About

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

  // MARK: - Guest Prompt

  private var guestPrompt: some View {
    VStack(alignment: .leading, spacing: 12) {
      Label {
        Text(String(localized: "Sign In"))
          .font(.subheadline.weight(.medium))
      } icon: {
        Image(systemName: "person.circle")
          .foregroundStyle(.secondary)
      }

      Text(String(localized: "Sign in to manage your profile, track devices, and access API keys."))
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .padding(Constants.standardPadding)
    .frame(maxWidth: .infinity, alignment: .leading)
    .glassEffect(in: .rect(cornerRadius: Constants.cornerRadius, style: .continuous))
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

  private var dangerZone: some View {
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

// MARK: - Appearance Helper

extension SettingsView {
  static func resolveColorScheme(_ value: String) -> ColorScheme? {
    switch value {
    case "light": .light
    case "dark": .dark
    default: nil
    }
  }
}

#Preview {
  SettingsView()
    .environment(AuthManager())
    .environment(SharingManager())
}
