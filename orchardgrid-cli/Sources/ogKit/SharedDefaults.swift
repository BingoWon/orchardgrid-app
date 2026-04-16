import Foundation

/// Read-side mirror of the GUI app's `OGSharedDefaults`. Both processes
/// agree on a single App Group suite + key constants — that's the entire
/// "shared state" contract.
///
/// On macOS, this requires the `com.apple.security.application-groups`
/// entitlement on the CLI binary, which is set when `og` is signed as
/// part of `make bundle-cli` (or the CI release flow). When `og` is run
/// outside the bundled context (e.g. `swift run` during dev) the App
/// Group container is unavailable and every getter returns nil — the
/// `og status` command surfaces this gracefully ("app not running /
/// not installed").
public enum SharedDefaults {
  public static let suiteName = "group.com.orchardgrid.shared"

  /// nil when this binary doesn't have the App Group entitlement.
  public static var store: UserDefaults? {
    UserDefaults(suiteName: suiteName)
  }

  public enum Key {
    public static let localEnabled = "OG.local.enabled"
    public static let localPort = "OG.local.port"
    public static let localRunning = "OG.local.running"
    public static let cloudEnabled = "OG.cloud.enabled"
    public static let cloudConnected = "OG.cloud.connected"
    /// `true` when the user has explicitly opted this device into the
    /// community pool. Defaults `false` — cloud-shared devices serve
    /// only their owner unless this is on.
    public static let cloudPublic = "OG.cloud.public"
    public static let enabledCapabilities = "OG.capabilities"
    public static let apiServerAuthToken = "OG.api.authToken"
  }

  // MARK: - Convenience getters

  public static var localEnabled: Bool { store?.bool(forKey: Key.localEnabled) ?? false }
  public static var localRunning: Bool { store?.bool(forKey: Key.localRunning) ?? false }
  public static var localPort: Int? {
    let p = store?.integer(forKey: Key.localPort) ?? 0
    return p > 0 ? p : nil
  }
  public static var cloudEnabled: Bool { store?.bool(forKey: Key.cloudEnabled) ?? false }
  public static var cloudPublic: Bool { store?.bool(forKey: Key.cloudPublic) ?? false }
  public static var enabledCapabilities: [String] {
    (store?.string(forKey: Key.enabledCapabilities) ?? "")
      .split(separator: ",").map(String.init).filter { !$0.isEmpty }
  }
}
