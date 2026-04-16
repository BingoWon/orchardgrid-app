import Foundation
import OrchardGridCore

/// CLI-side wrapper around the shared App Group `UserDefaults` suite.
/// Constants live in `OrchardGridCore.SharedDefaultsKeys` so the GUI
/// app sees the exact same keys — nothing here can drift from the
/// app definition.
///
/// On macOS this requires the `com.apple.security.application-groups`
/// entitlement on the CLI binary, which is set when `og` is signed as
/// part of `make bundle-cli` (or the CI release flow). When `og` is
/// run outside the bundled context (e.g. `swift run` during dev) the
/// App Group container is unavailable and every getter returns nil —
/// the `og status` command surfaces this gracefully ("app not running
/// / not installed").
public enum SharedDefaults {
  public static let suiteName = SharedDefaultsKeys.suiteName

  /// nil when this binary doesn't have the App Group entitlement.
  public static var store: UserDefaults? {
    UserDefaults(suiteName: suiteName)
  }

  public typealias Key = SharedDefaultsKeys

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
