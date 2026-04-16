import Foundation
import OrchardGridCore

/// App-side wrapper around the shared App Group `UserDefaults` suite.
/// Constants live in `OrchardGridCore.SharedDefaultsKeys` so the
/// bundled `og` CLI sees the exact same keys.
///
/// On macOS, this requires the `com.apple.security.application-groups`
/// entitlement on **both** the app and the CLI binary, signed with the
/// same Developer ID team.
enum OGSharedDefaults {
  static let suiteName = SharedDefaultsKeys.suiteName

  /// Lazily-resolved suite. Falls back to `UserDefaults.standard` when
  /// the App Group container is not provisioned (e.g. unsigned dev
  /// builds on a machine without the proper provisioning profile) so
  /// the app keeps working — sharing is silently disabled but nothing
  /// crashes.
  static let store: UserDefaults =
    UserDefaults(suiteName: suiteName) ?? .standard

  // Re-export Key namespace so view / manager code keeps the
  // `OGSharedDefaults.Key.*` access pattern.
  typealias Key = SharedDefaultsKeys
}
