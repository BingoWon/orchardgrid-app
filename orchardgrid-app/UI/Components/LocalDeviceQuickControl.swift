import FoundationModels
import SwiftUI

/// Quick control card for local device - displays Share to Cloud and Share Locally toggles
/// On macOS/iPad: navigates to sidebar; On iPhone: opens sheet
struct LocalDeviceQuickControl: View {
  @Environment(WebSocketClient.self) private var wsClient
  @Environment(APIServer.self) private var apiServer
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
            // macOS/iPad: Navigate to sidebar item
            navigationState.navigateTo(.localDevice)
          } else {
            // iPhone: Open sheet
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

      // Toggles Row
      HStack(spacing: 16) {
        // Share to Cloud
        ToggleCard(
          title: "Share to Cloud",
          isOn: Binding(
            get: { wsClient.isEnabled },
            set: { wsClient.isEnabled = $0 }
          ),
          isDisabled: !wsClient.canEnable,
          statusText: cloudStatusText
        )

        // Share Locally
        ToggleCard(
          title: "Share Locally",
          isOn: Binding(
            get: { apiServer.isEnabled },
            set: { apiServer.isEnabled = $0 }
          ),
          isDisabled: false,
          statusText: localStatusText
        )
      }
    }
    .padding(Constants.standardPadding)
    .glassEffect(in: .rect(cornerRadius: Constants.cornerRadius, style: .continuous))
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
  }

  // MARK: - Status Text

  private var cloudStatusText: String? {
    if !wsClient.canEnable {
      return unavailableReason
    }
    if wsClient.isEnabled {
      switch wsClient.connectionState {
      case .connecting:
        return "Connecting..."
      case .reconnecting:
        return "Reconnecting..."
      case .failed:
        return "Failed"
      default:
        return nil
      }
    }
    return nil
  }

  private var unavailableReason: String {
    switch wsClient.modelAvailability {
    case .unavailable(.deviceNotEligible):
      "Not Supported"
    case .unavailable(.appleIntelligenceNotEnabled):
      "Enable in Settings"
    case .unavailable(.modelNotReady):
      "Downloading..."
    default:
      "Unavailable"
    }
  }

  private var localStatusText: String? {
    if apiServer.isEnabled, !apiServer.isRunning {
      return "Starting..."
    }
    return nil
  }
}

// MARK: - Toggle Card

private struct ToggleCard: View {
  let title: String
  @Binding var isOn: Bool
  let isDisabled: Bool
  let statusText: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(.subheadline)
        .fontWeight(.medium)

      Toggle("", isOn: $isOn)
        .toggleStyle(.switch)
        .labelsHidden()
        .disabled(isDisabled)

      if let status = statusText {
        Text(status)
          .font(.caption)
          .foregroundStyle(isDisabled ? .orange : .secondary)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(12)
    .background(.ultraThinMaterial, in: .rect(cornerRadius: 10))
  }
}

#Preview {
  LocalDeviceQuickControl()
    .environment(WebSocketClient())
    .environment(APIServer())
    .environment(NavigationState())
    .padding()
}
