// MARK: - SharedDefaultsKeys
//
// Wire contract for the App Group `UserDefaults` suite shared between
// the GUI app and the bundled `og` CLI. Both processes need to agree
// on the suite identifier and key strings exactly — keeping the
// constants here, in `OrchardGridCore` (which both targets import),
// removes the previous parallel definitions that had to be edited
// in lockstep.
//
// Each side wraps these constants with its own getter / setter
// surface (the app gets typed @Observable bindings, the CLI gets
// nil-safe read-only getters that gracefully degrade when the App
// Group entitlement isn't provisioned). Both wrappers share the
// SAME suite + SAME keys.

public enum SharedDefaultsKeys {
  /// App Group identifier — matches every entitlements file (5 in
  /// total: macOS Debug/Release/DMG, iOS Debug/Release) AND the CLI's
  /// `og.entitlements`.
  public static let suiteName = "group.com.orchardgrid.shared"

  // MARK: - Keys

  /// Whether the user has Local Sharing enabled in the GUI.
  public static let localEnabled = "OG.local.enabled"
  /// The port the local OpenAI-compatible server is bound to.
  public static let localPort = "OG.local.port"
  /// Last observed local server status (running / stopped).
  public static let localRunning = "OG.local.running"
  /// Cloud sharing toggle.
  public static let cloudEnabled = "OG.cloud.enabled"
  /// Community-pool opt-in. False (default) = device only serves
  /// owner's own requests even when cloud-shared.
  public static let cloudPublic = "OG.cloud.public"
  /// Cloud connection state, surfaced as a string.
  public static let cloudConnected = "OG.cloud.connected"
  /// Comma-separated list of capability raw values currently enabled.
  public static let enabledCapabilities = "OG.capabilities"
  /// Optional Bearer token required by the local server.
  public static let apiServerAuthToken = "OG.api.authToken"
}
