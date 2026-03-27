import SwiftUI

#if os(macOS)
  import AppKit
#elseif os(iOS)
  import UIKit
#endif

struct CapabilityRow: View {
  let capability: Capability
  let isEnabled: Bool
  let isAvailable: Bool
  let unavailabilityReason: String?
  let needsSettingsRedirect: Bool
  let onToggle: (Bool) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 12) {
        Image(systemName: capability.icon)
          .font(.body)
          .foregroundStyle(isAvailable ? .primary : .tertiary)
          .frame(width: 24)

        Text(capability.displayName)
          .font(.subheadline)
          .fontWeight(.medium)
          .foregroundStyle(isAvailable ? .primary : .tertiary)

        Spacer()

        if !isAvailable {
          Text(String(localized: "Unavailable"))
            .font(.caption)
            .foregroundStyle(.tertiary)
        }

        Toggle(
          "",
          isOn: Binding(
            get: { isEnabled && isAvailable },
            set: { onToggle($0) }
          )
        )
        .toggleStyle(.switch)
        .labelsHidden()
        .disabled(!isAvailable)
      }

      if !isAvailable, let reason = unavailabilityReason {
        VStack(alignment: .leading, spacing: 4) {
          Text(reason)
            .font(.caption2)
            .foregroundStyle(.secondary)

          if needsSettingsRedirect {
            settingsButton
          }
        }
        .padding(.leading, 36)
      }
    }
    .padding(.vertical, 8)
  }

  @ViewBuilder
  private var settingsButton: some View {
    #if os(iOS)
      Button {
        if let url = URL(string: "App-Prefs:Privacy&path=SPEECH_RECOGNITION") {
          UIApplication.shared.open(url) { success in
            if !success, let fallback = URL(string: UIApplication.openSettingsURLString) {
              UIApplication.shared.open(fallback)
            }
          }
        }
      } label: {
        Label(String(localized: "Open Settings"), systemImage: "gear")
          .font(.caption2)
      }
      .buttonStyle(.bordered)
      .controlSize(.mini)
    #elseif os(macOS)
      Button {
        if let url = URL(
          string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition"
        ) {
          NSWorkspace.shared.open(url)
        }
      } label: {
        Label(String(localized: "Open System Settings"), systemImage: "gear")
          .font(.caption2)
      }
      .buttonStyle(.bordered)
      .controlSize(.mini)
    #endif
  }
}
