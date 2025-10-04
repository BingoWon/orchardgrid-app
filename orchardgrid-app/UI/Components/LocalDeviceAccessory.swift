import SwiftUI

/// Tab View Bottom Accessory - 显示本设备的 Platform Connection 状态
/// 类似 Apple Music 的 MiniPlayer，提供快速访问本设备连接信息的入口
struct LocalDeviceAccessory: View {
  @Environment(\.tabViewBottomAccessoryPlacement) private var placement
  @Environment(WebSocketClient.self) private var wsClient
  @State private var showDeviceSheet = false

  var body: some View {
    Button {
      showDeviceSheet = true
    } label: {
      if placement == .inline {
        inlineView
      } else {
        expandedView
      }
    }
    .buttonStyle(.plain)
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

  // MARK: - Inline View

  private var inlineView: some View {
    GeometryReader { geometry in
      HStack(spacing: 10) {
        HStack(spacing: 8) {
          connectionIndicator(size: 8)
          Text(NavigationItem.localDeviceTitle)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.primary)
        }
        .padding(.leading, geometry.size.height / 2)

        Spacer()

        Text(connectionStatusText)
          .font(.system(size: 14, weight: .medium))
          .foregroundStyle(.secondary)
          .padding(.trailing, geometry.size.height / 2)
      }
      .frame(width: geometry.size.width, height: geometry.size.height)
      .glassEffect(in: Capsule())
    }
  }

  // MARK: - Expanded View

  private var expandedView: some View {
    GeometryReader { geometry in
      HStack(spacing: 12) {
        HStack(spacing: 8) {
          connectionIndicator(size: 10)
          Text(NavigationItem.localDeviceTitle)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.primary)
        }
        .padding(.leading, geometry.size.height / 2)

        Spacer(minLength: 12)

        HStack(spacing: 8) {
          Text(connectionStatusText)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.secondary)

          if wsClient.isConnected {
            Text("•")
              .font(.system(size: 12))
              .foregroundStyle(.tertiary)

            Text("\(wsClient.tasksProcessed)")
              .font(.system(size: 14, weight: .semibold))
              .foregroundStyle(.primary)
          }
        }

        Image(systemName: "chevron.right")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(.tertiary)
          .padding(.trailing, geometry.size.height / 2)
      }
      .frame(width: geometry.size.width, height: geometry.size.height)
      .glassEffect(in: Capsule())
    }
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
