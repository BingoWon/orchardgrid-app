import SwiftUI

/// Tab View Bottom Accessory - shows this device's Platform Connection status
/// Similar to Apple Music's MiniPlayer, provides quick access to the local device connection info
struct LocalDeviceAccessory: View {
  @Environment(\.tabViewBottomAccessoryPlacement) private var placement
  @Environment(WebSocketClient.self) private var wsClient
  @State private var showDeviceSheet = false

  var body: some View {
    Group {
      switch placement {
      case .inline:
        inlineView
      case .expanded, nil:
        expandedView
      @unknown default:
        expandedView
      }
    }
    .contentShape(Rectangle())
    .onTapGesture {
      showDeviceSheet = true
    }
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

  // MARK: - Inline View

  private var inlineView: some View {
    HStack {
      connectionIndicator(size: 8)

      Spacer()

      Text(connectionStatusText)
        .font(.subheadline)
        .foregroundStyle(.secondary)

      Spacer()

      Image(systemName: "chevron.right")
        .font(.caption)
        .foregroundStyle(.tertiary)
    }
    .padding(.horizontal)
  }

  // MARK: - Expanded View

  private var expandedView: some View {
    HStack {
      HStack(spacing: 8) {
        connectionIndicator(size: 10)
        Text(NavigationItem.localDeviceTitle)
          .font(.headline)
      }

      Spacer()

      HStack(spacing: 8) {
        Text(connectionStatusText)
          .font(.subheadline)
          .foregroundStyle(.secondary)

        if wsClient.isConnected {
          Text("-")
            .foregroundStyle(.tertiary)

          Text("\(wsClient.tasksProcessed)")
            .font(.subheadline)
            .fontWeight(.semibold)
        }
      }

      Image(systemName: "chevron.right")
        .font(.caption)
        .foregroundStyle(.tertiary)
    }
    .padding(.horizontal)
  }

  // MARK: - Helpers

  private func connectionIndicator(size: CGFloat) -> some View {
    Circle()
      .fill(connectionColor)
      .frame(width: size, height: size)
  }

  private var connectionColor: Color {
    switch wsClient.connectionState {
    case .connected:
      .green
    case .connecting, .reconnecting:
      .orange
    default:
      .gray
    }
  }

  private var connectionStatusText: String {
    switch wsClient.connectionState {
    case .connected:
      "Connected"
    case .connecting:
      "Connecting..."
    case .reconnecting:
      "Reconnecting..."
    case .disconnected:
      "Disconnected"
    case .failed:
      "Failed"
    }
  }
}
