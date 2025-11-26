import SwiftUI

/// Tab View Bottom Accessory - displays both sharing modes status
/// Similar to Apple Music's Now Playing, tapping opens the full device view
struct LocalDeviceAccessory: View {
  @Environment(\.tabViewBottomAccessoryPlacement) private var placement
  @Environment(SharingManager.self) private var sharing
  @Binding var showSheet: Bool

  var body: some View {
    Group {
      switch placement {
      case .expanded:
        expandedView
      case .inline:
        inlineView
      default:
        expandedView
      }
    }
    .contentShape(Rectangle())
    .onTapGesture {
      showSheet = true
    }
  }

  // MARK: - Expanded View

  private var expandedView: some View {
    HStack {
      Text(NavigationItem.localDeviceTitle)
        .font(.subheadline)
        .fontWeight(.semibold)

      Spacer()

      HStack(spacing: 16) {
        cloudStatus
        localStatus
      }
    }
    .padding(.horizontal)
  }

  // MARK: - Inline View

  private var inlineView: some View {
    HStack {
      Spacer()
      cloudStatus
      Spacer()
      localStatus
      Spacer()
    }
  }

  // MARK: - Status Components

  private var cloudStatus: some View {
    HStack(spacing: 6) {
      Circle()
        .fill(cloudIndicatorColor)
        .frame(width: 8, height: 8)

      Text("Cloud")
        .font(.subheadline)

      if sharing.wantsCloudSharing {
        Text("\(sharing.cloudTasksProcessed)")
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .monospacedDigit()
      }
    }
  }

  private var localStatus: some View {
    HStack(spacing: 6) {
      Circle()
        .fill(localIndicatorColor)
        .frame(width: 8, height: 8)

      Text("Local")
        .font(.subheadline)

      if sharing.wantsLocalSharing {
        Text("\(sharing.localRequestCount)")
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .monospacedDigit()
      }
    }
  }

  // MARK: - Indicator Colors

  private var cloudIndicatorColor: Color {
    guard sharing.wantsCloudSharing else { return .gray.opacity(0.5) }

    switch sharing.cloudConnectionState {
    case .connected:
      return .green
    case .connecting, .reconnecting:
      return .orange
    case .failed:
      return .red
    default:
      return .gray
    }
  }

  private var localIndicatorColor: Color {
    guard sharing.wantsLocalSharing else { return .gray.opacity(0.5) }
    return sharing.isLocalActive ? .green : .orange
  }
}
