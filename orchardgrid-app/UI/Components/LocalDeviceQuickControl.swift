import FoundationModels
import SwiftUI

/// Quick control card for local device - displays AI status and sharing toggles
struct LocalDeviceQuickControl: View {
  @Environment(SharingManager.self) private var sharing
  @Environment(NavigationState.self) private var navigationState
  @State private var showDeviceSheet = false
  @Environment(\.isWideLayout) private var isWideLayout

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text(NavigationItem.localDeviceTitle)
          .font(.headline)
          .foregroundStyle(.secondary)

        Spacer()

        HStack(spacing: 4) {
          Text(String(localized: "Details"))
            .font(.subheadline)
          Image(systemName: "chevron.right")
            .font(.caption)
        }
        .foregroundStyle(.blue)
      }

      if !sharing.isModelAvailable {
        aiUnavailableStatus
      } else {
        togglesRow
      }
    }
    .padding(Constants.standardPadding)
    .glassEffect(in: .rect(cornerRadius: Constants.cornerRadius, style: .continuous))
    .contentShape(Rectangle())
    .onTapGesture { navigateToDetails() }
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
        Text(String(localized: "Tap Details for more information"))
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer()
    }
    .padding(12)
    .background(.ultraThinMaterial, in: .rect(cornerRadius: 10))
  }

  private var statusIcon: String { sharing.modelAvailability.statusIcon }
  private var statusColor: Color { sharing.modelAvailability.statusColor }
  private var statusTitle: String { sharing.modelAvailability.statusTitle }

  private func navigateToDetails() {
    if isWideLayout {
      navigationState.selectedItem = .localDevice
    } else {
      showDeviceSheet = true
    }
  }

  // MARK: - Toggles

  private var isLocalStarting: Bool {
    sharing.wantsLocalSharing && !sharing.isLocalActive
      && !sharing.localPortConflict && sharing.localErrorMessage == nil
  }

  private var togglesRow: some View {
    VStack(spacing: 8) {
      ToggleRow(
        title: String(localized: "Share to Cloud"),
        isOn: Binding(
          get: { sharing.wantsCloudSharing },
          set: { sharing.setCloudSharing($0) }
        ),
        statusText: cloudStatusText
      )

      ToggleRow(
        title: String(localized: "Share Locally"),
        isOn: Binding(
          get: { sharing.isLocalActive },
          set: { sharing.setLocalSharing($0) }
        ),
        statusText: localStatusText,
        isLoading: isLocalStarting
      )
    }
  }

  // MARK: - Status Text

  private var cloudStatusText: String? {
    guard sharing.wantsCloudSharing else { return nil }
    switch sharing.cloudConnectionState {
    case .connecting:
      return String(localized: "Connecting...")
    case .reconnecting:
      return String(localized: "Reconnecting...")
    case .failed:
      return String(localized: "Failed")
    case .connected:
      return String(localized: "Connected")
    default:
      return nil
    }
  }

  private var localStatusText: String? {
    guard sharing.wantsLocalSharing else { return nil }
    if sharing.localPortConflict { return String(localized: "Port conflict") }
    if sharing.isLocalActive { return String(localized: "Running") }
    return String(localized: "Starting...")
  }
}

// MARK: - Toggle Row

private struct ToggleRow: View {
  let title: String
  @Binding var isOn: Bool
  let statusText: String?
  var isLoading = false

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

      if isLoading {
        ProgressView()
          .controlSize(.small)
      } else {
        Toggle("", isOn: $isOn)
          .toggleStyle(.switch)
          .labelsHidden()
      }
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
