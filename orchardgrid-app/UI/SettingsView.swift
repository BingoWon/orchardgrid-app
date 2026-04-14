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
  @AppStorage("AppAppearance") private var appAppearance = "system"
  @State private var showRestartAlert = false

  /// Reads the current effective language for the Picker's initial selection.
  @State private var selectedLanguage: String = {
    if let langs = UserDefaults.standard.array(forKey: "AppleLanguages") as? [String],
      let first = langs.first
    {
      // Normalize: "en-US" → "en", "zh-Hans-US" → "zh-Hans"
      if first.hasPrefix("zh-Hans") { return "zh-Hans" }
      if first.hasPrefix("zh") { return "zh-Hans" }
      let base = first.components(separatedBy: "-").first ?? first
      if base == "en" { return "en" }
      return first
    }
    return "system"
  }()

  private let repoURL = URL(string: "https://github.com/BingoWon/orchardgrid-app")!

  var body: some View {
    ScrollView {
      GlassEffectContainer(spacing: Constants.standardSpacing) {
        VStack(alignment: .leading, spacing: Constants.standardSpacing) {
          // Account — always at top
          if authManager.isAuthenticated {
            profileCard
          } else {
            guestSignInCard
          }

          // Shared Capabilities
          capabilitiesSection

          // Preferences (Appearance + Language)
          preferencesSection

          // About
          sourceCodeRow

          // Destructive actions (auth only, always at bottom)
          if authManager.isAuthenticated {
            signOutButton
            dangerZone
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
        "This action cannot be undone. All your devices, API keys, and logs will be deleted."
      )
    }
    .alert(String(localized: "Language Changed"), isPresented: $showRestartAlert) {
      Button(String(localized: "OK")) {}
    } message: {
      Text("The app needs to restart to apply the new language.")
    }
  }

  // MARK: - Shared Capabilities

  private var capabilitiesSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .top, spacing: 10) {
        Image(systemName: "cpu")
          .font(.subheadline)
          .foregroundStyle(.primary)
          .frame(width: 20)
          .padding(.top, 1)

        VStack(alignment: .leading, spacing: 2) {
          Text(String(localized: "Shared Capabilities"))
            .font(.subheadline.weight(.medium))
          Text(String(localized: "Choose which AI features this device shares"))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
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
        .font(.subheadline)
      }
      .padding(.vertical, 10)

      Divider()

      // Language
      HStack {
        Label(String(localized: "Language"), systemImage: "globe")
          .font(.subheadline.weight(.medium))

        Spacer()

        Picker(String(localized: "Language"), selection: $selectedLanguage) {
          Text(String(localized: "System")).tag("system")
          Text("English").tag("en")
          Text("中文").tag("zh-Hans")
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .font(.subheadline)
        .onChange(of: selectedLanguage) {
          if selectedLanguage == "system" {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
          } else {
            UserDefaults.standard.set([selectedLanguage], forKey: "AppleLanguages")
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

  // MARK: - Guest Sign In

  private var guestSignInCard: some View {
    HStack(spacing: 12) {
      Image(systemName: "person.circle.fill")
        .font(.title2)
        .foregroundStyle(.secondary)

      VStack(alignment: .leading, spacing: 2) {
        Text(String(localized: "Sign In"))
          .font(.headline)
        Text(String(localized: "Manage your profile, devices, and API keys"))
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer()

      Image(systemName: "chevron.right")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.tertiary)
    }
    .padding(Constants.standardPadding)
    .glassEffect(in: .rect(cornerRadius: Constants.cornerRadius, style: .continuous))
    .contentShape(Rectangle())
    .onTapGesture {
      authManager.showAuthSheet = true
    }
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

      Text("Permanently removes your account, devices, API keys, and all logs.")
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
    .environment(AuthManager(api: .preview))
    .environment(SharingManager())
}
