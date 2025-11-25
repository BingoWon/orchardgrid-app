import FoundationModels
import SwiftUI

/// Quick control card for This Mac - displays Share to Cloud and Share Locally toggles
struct LocalDeviceQuickControl: View {
  @Environment(WebSocketClient.self) private var wsClient
  @Environment(APIServer.self) private var apiServer
  @State private var showDeviceSheet = false

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      // Header
      HStack {
        Text(NavigationItem.localDeviceTitle)
          .font(.headline)
          .foregroundStyle(.secondary)

        Spacer()

        Button {
          showDeviceSheet = true
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
          #if !os(macOS)
          .navigationBarTitleDisplayMode(.inline)
          #endif
          .toolbar {
            #if os(macOS)
            ToolbarItem(placement: .automatic) {
              Button("Close") {
                showDeviceSheet = false
              }
            }
            #else
            ToolbarItem(placement: .topBarTrailing) {
              Button(role: .close) {
                showDeviceSheet = false
              }
            }
            #endif
          }
      }
      #if !os(macOS)
      .presentationDetents([.large])
      .presentationDragIndicator(.visible)
      #endif
    }
  }

  // MARK: - Status Text

  private var cloudStatusText: String? {
    // Only show status when there's something to report
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
      return "Not Supported"
    case .unavailable(.appleIntelligenceNotEnabled):
      return "Enable in Settings"
    case .unavailable(.modelNotReady):
      return "Downloading..."
    default:
      return "Unavailable"
    }
  }

  private var localStatusText: String? {
    if apiServer.isEnabled && !apiServer.isRunning {
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
    .padding()
}

