import FoundationModels
import SwiftUI
#if os(macOS)
  import AppKit
#elseif os(iOS)
  import UIKit
#endif

struct LocalDeviceView: View {
  @Environment(SharingManager.self) private var sharing
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass

  private var isWideLayout: Bool {
    #if os(macOS)
      return true
    #else
      return horizontalSizeClass == .regular
    #endif
  }

  var body: some View {
    ScrollView {
      GlassEffectContainer {
        VStack(alignment: .leading, spacing: 16) {
          if !sharing.isModelAvailable {
            AIStatusCard(availability: sharing.modelAvailability)
          } else {
            if isWideLayout {
              HStack(alignment: .top, spacing: 16) {
                cloudShareCard
                localShareCard
              }
            } else {
              VStack(alignment: .leading, spacing: 16) {
                cloudShareCard
                localShareCard
              }
            }
          }
        }
        .padding()
      }
    }
    .navigationTitle(DeviceInfo.deviceName)
  }

  // MARK: - Share to Cloud Card

  private var cloudShareCard: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        VStack(alignment: .leading, spacing: 4) {
          Text("Share to Cloud")
            .font(.headline)
          Text("Contribute computing power to OrchardGrid")
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Spacer()

        Toggle("", isOn: Binding(
          get: { sharing.wantsCloudSharing },
          set: { sharing.setCloudSharing($0) }
        ))
        .toggleStyle(.switch)
      }

      if sharing.wantsCloudSharing {
        Divider()
        cloudConnectionStatus
      }
    }
    .padding()
    .frame(maxWidth: .infinity, alignment: .leading)
    .glassEffect(in: .rect(cornerRadius: 12, style: .continuous))
  }

  @ViewBuilder
  private var cloudConnectionStatus: some View {
    switch sharing.cloudConnectionState {
    case .disconnected:
      StatusRow(
        icon: "circle",
        iconColor: .secondary,
        title: "Disconnected",
        subtitle: "Enable to start connecting"
      )

    case .connecting:
      StatusRow(
        isLoading: true,
        title: "Connecting...",
        subtitle: "Establishing connection"
      )

    case .connected:
      StatusRow(
        icon: "checkmark.circle.fill",
        iconColor: .green,
        title: "Connected",
        subtitle: "Ready to process tasks"
      )

      Divider()

      VStack(alignment: .leading, spacing: 12) {
        InfoRow(label: "Device", value: DeviceInfo.deviceName)
        InfoRow(label: "Chip", value: DeviceInfo.chipModel)
        InfoRow(label: "Memory", value: DeviceInfo.formattedMemory)
      }

      Divider()

      HStack(spacing: 40) {
        StatView(title: "Tasks Processed", value: "\(sharing.cloudTasksProcessed)")
        StatView(title: "Hardware ID", value: String(DeviceID.current.prefix(8)))
      }

    case let .reconnecting(attempt, nextRetryIn):
      VStack(alignment: .leading, spacing: 12) {
        StatusRow(
          isLoading: true,
          title: "Reconnecting...",
          subtitle: nextRetryIn.map { "Attempt \(attempt), next retry in \(Int($0))s" }
            ?? "Attempt \(attempt)"
        )

        Button("Retry Now") {
          sharing.retryCloudConnection()
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
      }

    case let .failed(error):
      VStack(alignment: .leading, spacing: 12) {
        StatusRow(
          icon: "exclamationmark.triangle.fill",
          iconColor: .orange,
          title: "Connection Failed",
          subtitle: error
        )

        Button("Retry") {
          sharing.retryCloudConnection()
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
      }
    }
  }

  // MARK: - Share Locally Card

  private var localShareCard: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        VStack(alignment: .leading, spacing: 4) {
          Text("Share Locally")
            .font(.headline)
          Text("Standard Chat Completion API for local apps")
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Spacer()

        Toggle("", isOn: Binding(
          get: { sharing.wantsLocalSharing },
          set: { sharing.setLocalSharing($0) }
        ))
        .toggleStyle(.switch)
      }

      if sharing.wantsLocalSharing {
        Divider()

        StatusRow(
          icon: sharing.isLocalActive ? "checkmark.circle.fill" : "hourglass.circle.fill",
          iconColor: sharing.isLocalActive ? .green : .orange,
          title: sharing.isLocalActive ? "Running" : "Starting...",
          subtitle: "Port \(sharing.localPort)"
        )

        if sharing.isLocalActive {
          Divider()

          VStack(alignment: .leading, spacing: 12) {
            InfoRow(label: "Model", value: "apple-intelligence")
            EndpointRow(
              label: "Local",
              url: "http://localhost:\(sharing.localPort)/v1/chat/completions"
            )
            if let localIP = sharing.localIPAddress {
              EndpointRow(
                label: "Network",
                url: "http://\(localIP):\(sharing.localPort)/v1/chat/completions"
              )
            }
          }

          Divider()

          HStack(spacing: 40) {
            StatView(title: "Requests Served", value: "\(sharing.localRequestCount)")
          }
        }
      }
    }
    .padding()
    .frame(maxWidth: .infinity, alignment: .leading)
    .glassEffect(in: .rect(cornerRadius: 12, style: .continuous))
  }
}

// MARK: - AI Status Card

struct AIStatusCard: View {
  let availability: SystemLanguageModel.Availability

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Image(systemName: headerIcon)
          .foregroundStyle(headerColor)
          .font(.title2)
        Text(headerTitle)
          .font(.headline)
      }

      Text("Both sharing modes require Apple Intelligence to function.")
        .font(.subheadline)
        .foregroundStyle(.secondary)

      Divider()

      statusContent
    }
    .padding()
    .frame(maxWidth: .infinity, alignment: .leading)
    .glassEffect(in: .rect(cornerRadius: 12, style: .continuous))
  }

  private var headerIcon: String {
    switch availability {
    case .available:
      "checkmark.circle.fill"
    case .unavailable(.modelNotReady):
      "arrow.down.circle"
    default:
      "exclamationmark.triangle.fill"
    }
  }

  private var headerColor: Color {
    switch availability {
    case .available:
      .green
    case .unavailable(.modelNotReady):
      .blue
    default:
      .orange
    }
  }

  private var headerTitle: String {
    switch availability {
    case .available:
      "Apple Intelligence Ready"
    case .unavailable(.deviceNotEligible):
      "Device Not Supported"
    case .unavailable(.appleIntelligenceNotEnabled):
      "Apple Intelligence Not Enabled"
    case .unavailable(.modelNotReady):
      "Downloading Model..."
    case .unavailable:
      "Apple Intelligence Unavailable"
    }
  }

  @ViewBuilder
  private var statusContent: some View {
    switch availability {
    case .available:
      EmptyView()

    case .unavailable(.deviceNotEligible):
      VStack(alignment: .leading, spacing: 12) {
        Text("This device doesn't support Apple Intelligence. Compatible devices include:")
          .font(.caption)
          .foregroundStyle(.secondary)

        VStack(alignment: .leading, spacing: 6) {
          Label("iPhone 15 Pro or later", systemImage: "iphone")
          Label("iPad with M1 chip or later", systemImage: "ipad")
          Label("Mac with Apple Silicon", systemImage: "desktopcomputer")
        }
        .font(.caption)
        .foregroundStyle(.secondary)

        Link("Learn More", destination: URL(string: "https://www.apple.com/apple-intelligence/")!)
          .font(.caption)
          .buttonStyle(.borderedProminent)
          .controlSize(.small)
      }

    case .unavailable(.appleIntelligenceNotEnabled):
      VStack(alignment: .leading, spacing: 12) {
        Text("Enable Apple Intelligence in Settings to use this app.")
          .font(.caption)
          .foregroundStyle(.secondary)

        #if os(iOS)
          Button("Open Settings") {
            if let url = URL(string: UIApplication.openSettingsURLString) {
              UIApplication.shared.open(url)
            }
          }
          .buttonStyle(.borderedProminent)
          .controlSize(.small)
        #elseif os(macOS)
          Button("Open System Settings") {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security") {
              NSWorkspace.shared.open(url)
            }
          }
          .buttonStyle(.borderedProminent)
          .controlSize(.small)
        #endif

        Text("After enabling, restart this app.")
          .font(.caption2)
          .foregroundStyle(.tertiary)
      }

    case .unavailable(.modelNotReady):
      VStack(alignment: .leading, spacing: 12) {
        HStack(spacing: 8) {
          ProgressView()
            .controlSize(.small)
          Text("The on-device model is being downloaded.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Text("This may take a while. Sharing modes will be available once the download completes.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

    case .unavailable:
      VStack(alignment: .leading, spacing: 8) {
        Text("The on-device model is currently unavailable.")
          .font(.caption)
          .foregroundStyle(.secondary)

        Text("Please try again later or contact support if the issue persists.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }
}

// MARK: - Supporting Views

struct StatusRow: View {
  var icon: String?
  var iconColor: Color = .secondary
  var isLoading: Bool = false
  let title: String
  let subtitle: String

  var body: some View {
    HStack {
      if isLoading {
        ProgressView()
          .controlSize(.small)
      } else if let icon {
        Image(systemName: icon)
          .foregroundStyle(iconColor)
      }

      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.subheadline)
          .fontWeight(.medium)
        Text(subtitle)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer()
    }
  }
}

struct InfoRow: View {
  let label: String
  let value: String

  var body: some View {
    HStack(alignment: .top, spacing: 8) {
      Text(label)
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(width: 60, alignment: .leading)

      Text(value)
        .font(.caption)
        .fontWeight(.medium)
        .textSelection(.enabled)

      Spacer()
    }
  }
}

struct EndpointRow: View {
  let label: String
  let url: String

  var body: some View {
    HStack(alignment: .top, spacing: 8) {
      Text(label)
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(width: 60, alignment: .leading)

      Text(url)
        .font(.caption)
        .fontWeight(.medium)
        .textSelection(.enabled)
        .lineLimit(2)
        .fixedSize(horizontal: false, vertical: true)

      Spacer()

      Button {
        copyToClipboard(url)
      } label: {
        Image(systemName: "doc.on.doc")
          .font(.caption)
          .foregroundStyle(.blue)
      }
      .buttonStyle(.plain)
      .help("Copy URL")
    }
  }

  private func copyToClipboard(_ text: String) {
    #if os(macOS)
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(text, forType: .string)
    #elseif os(iOS)
      UIPasteboard.general.string = text
    #endif
  }
}

struct StatView: View {
  let title: String
  let value: String

  var body: some View {
    VStack(spacing: 4) {
      Text(value)
        .font(.title3.bold())
      Text(title)
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }
}

#Preview {
  LocalDeviceView()
    .environment(SharingManager())
}
