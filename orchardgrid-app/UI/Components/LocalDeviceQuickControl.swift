import FoundationModels
import SwiftUI

/// Quick control card for local device - displays AI status and sharing toggles
struct LocalDeviceQuickControl: View {
  @Environment(SharingManager.self) private var sharing
  @Environment(NavigationState.self) private var navigationState
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @State private var showDeviceSheet = false

  private var isWideLayout: Bool {
    #if os(macOS)
      return true
    #else
      return horizontalSizeClass == .regular
    #endif
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      // Header
      HStack {
        Text(NavigationItem.localDeviceTitle)
          .font(.headline)
          .foregroundStyle(.secondary)

        Spacer()

        Button {
          if isWideLayout {
            navigationState.navigateTo(.localDevice)
          } else {
            showDeviceSheet = true
          }
        } label: {
          HStack(spacing: 4) {
            Text("Details")
              .font(.subheadline)
            Image(systemName: "chevron.right")
              .font(.caption)
          }
          .foregroundStyle(.blue)
        }
        .buttonStyle(.plain)
      }

      // AI Status or Toggles
      if !sharing.isModelAvailable {
        aiUnavailableStatus
      } else {
        togglesRow
      }
    }
    .padding(Constants.standardPadding)
    .glassEffect(in: .rect(cornerRadius: Constants.cornerRadius, style: .continuous))
    #if !os(macOS)
      .sheet(isPresented: $showDeviceSheet) {
        NavigationStack {
          LocalDeviceView()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
              ToolbarItem(placement: .topBarTrailing) {
                Button(role: .close) {
                  showDeviceSheet = false
                }
              }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
      }
    #endif
  }

  // MARK: - AI Unavailable Status

  private var aiUnavailableStatus: some View {
    HStack(spacing: 12) {
      Image(systemName: statusIcon)
        .foregroundStyle(statusColor)
        .font(.title2)

      VStack(alignment: .leading, spacing: 2) {
        Text(statusTitle)
          .font(.subheadline)
          .fontWeight(.medium)
        Text("Tap Details for more information")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer()
    }
    .padding(12)
    .background(.ultraThinMaterial, in: .rect(cornerRadius: 10))
  }

  private var statusIcon: String {
    switch sharing.modelAvailability {
    case .unavailable(.modelNotReady):
      "arrow.down.circle"
    default:
      "exclamationmark.triangle.fill"
    }
  }

  private var statusColor: Color {
    switch sharing.modelAvailability {
    case .unavailable(.modelNotReady):
      .blue
    default:
      .orange
    }
  }

  private var statusTitle: String {
    switch sharing.modelAvailability {
    case .unavailable(.deviceNotEligible):
      "Device Not Supported"
    case .unavailable(.appleIntelligenceNotEnabled):
      "Apple Intelligence Disabled"
    case .unavailable(.modelNotReady):
      "Downloading Model..."
    default:
      "Apple Intelligence Unavailable"
    }
  }

  // MARK: - Toggles

  private var togglesRow: some View {
    VStack(spacing: 8) {
      ToggleRow(
        title: "Share to Cloud",
        isOn: Binding(
          get: { sharing.wantsCloudSharing },
          set: { sharing.setCloudSharing($0) }
        ),
        statusText: cloudStatusText
      )

      ToggleRow(
        title: "Share Locally",
        isOn: Binding(
          get: { sharing.wantsLocalSharing },
          set: { sharing.setLocalSharing($0) }
        ),
        statusText: localStatusText
      )
    }
  }

  // MARK: - Status Text

  private var cloudStatusText: String? {
    guard sharing.wantsCloudSharing else { return nil }
    switch sharing.cloudConnectionState {
    case .connecting:
      return "Connecting..."
    case .reconnecting:
      return "Reconnecting..."
    case .failed:
      return "Failed"
    case .connected:
      return "Connected"
    default:
      return nil
    }
  }

  private var localStatusText: String? {
    guard sharing.wantsLocalSharing else { return nil }
    return sharing.isLocalActive ? "Running" : "Starting..."
  }
}

// MARK: - Toggle Row

private struct ToggleRow: View {
  let title: String
  @Binding var isOn: Bool
  let statusText: String?

  var body: some View {
    HStack {
      Text(title)
        .font(.subheadline)
        .fontWeight(.medium)

      Spacer()

      if let status = statusText {
        Text(status)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Toggle("", isOn: $isOn)
        .toggleStyle(.switch)
        .labelsHidden()
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .background(.ultraThinMaterial, in: .rect(cornerRadius: 10))
  }
}

#Preview {
  LocalDeviceQuickControl()
    .environment(SharingManager())
    .environment(NavigationState())
    .padding()
}
