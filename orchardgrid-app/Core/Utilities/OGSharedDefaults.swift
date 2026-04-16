import Foundation

/// Single source of truth for state shared between the GUI app and the
/// bundled `og` CLI. Both processes read/write the same App Group
/// UserDefaults suite (`group.com.orchardgrid.shared`) using the keys
/// declared here.
///
/// On macOS, this requires the `com.apple.security.application-groups`
/// entitlement on **both** the app and the CLI binary, signed with the
/// same Developer ID team.
enum OGSharedDefaults {
  /// App Group identifier — must match every entitlements file (5 in
  /// total: macOS Debug/Release/DMG, iOS Debug/Release) AND the CLI's
  /// `og.entitlements`.
  static let suiteName = "group.com.orchardgrid.shared"

  /// Lazily-resolved suite. Falls back to `UserDefaults.standard` when
  /// the App Group container is not provisioned (e.g. unsigned dev
  /// builds on a machine without the proper provisioning profile) so
  /// the app keeps working — sharing is silently disabled but nothing
  /// crashes.
  static let store: UserDefaults =
    UserDefaults(suiteName: suiteName) ?? .standard

  // MARK: - Keys

  enum Key {
    /// Whether the user has Local Sharing enabled in the GUI.
    static let localEnabled = "OG.local.enabled"
    /// The port the local OpenAI-compatible server is bound to.
    static let localPort = "OG.local.port"
    /// Last observed local server status (running / stopped).
    static let localRunning = "OG.local.running"
    /// Cloud sharing toggle.
    static let cloudEnabled = "OG.cloud.enabled"
    /// Community-pool opt-in. False (default) = device only serves
    /// owner's own requests even when cloud-shared.
    static let cloudPublic = "OG.cloud.public"
    /// Cloud connection state, surfaced as a string.
    static let cloudConnected = "OG.cloud.connected"
    /// Comma-separated list of capability raw values currently enabled.
    static let enabledCapabilities = "OG.capabilities"
    /// Optional Bearer token required by the local server.
    static let apiServerAuthToken = "OG.api.authToken"
  }
}
