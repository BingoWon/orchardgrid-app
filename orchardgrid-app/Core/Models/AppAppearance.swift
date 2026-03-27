import SwiftUI

/// Centralized appearance / color‑scheme resolver.
/// Both `OrchardGridApp` and `SettingsView` share the same `@AppStorage("AppAppearance")` key.
enum AppAppearance {
  static func colorScheme(for value: String) -> ColorScheme? {
    switch value {
    case "light": .light
    case "dark": .dark
    default: nil
    }
  }
}
