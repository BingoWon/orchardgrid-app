import FoundationModels
import OrchardGridCore
import SwiftUI

#if os(macOS)
  import AppKit
#elseif os(iOS)
  import UIKit
#endif

struct LocalDeviceView: View {
  @Environment(SharingManager.self) private var sharing
  @Environment(\.isWideLayout) private var isWideLayout

  var body: some View {
    ScrollView {
      GlassEffectContainer(spacing: 16) {
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
          Text(String(localized: "Share to Cloud"))
            .font(.headline)
          Text(
            String(
              localized:
                "Connect this device to OrchardGrid so you can reach it from anywhere."
            )
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }

        Spacer()

        Toggle(
          "",
          isOn: Binding(
            get: { sharing.wantsCloudSharing },
            set: { sharing.setCloudSharing($0) }
          )
        )
        .toggleStyle(.switch)
      }

      if sharing.wantsCloudSharing {
        Divider()
        publicSharingRow
        Divider()
        cloudConnectionStatus
      }
    }
    .padding()
    .frame(maxWidth: .infinity, alignment: .leading)
    .glassEffect(in: .rect(cornerRadius: 12, style: .continuous))
  }

  // MARK: - Community pool opt-in (informed consent)
  //
  // Off (default): cloud-shared, but only the owner's own requests
  // route here. On: device joins the community pool, serves any
  // signed-in OrchardGrid user.

  private var publicSharingRow: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        VStack(alignment: .leading, spacing: 4) {
          Text(String(localized: "Make available to others"))
            .font(.subheadline.weight(.medium))
          Text(
            String(
              localized:
                "When on, this device serves inference requests from any signed-in OrchardGrid user — not just you. Apple's built-in safety guardrails still apply, and you can turn this off anytime."
            )
          )
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        }

        Spacer()

        Toggle(
          "",
          isOn: Binding(
            get: { sharing.wantsPublicSharing },
            set: { sharing.setPublicSharing($0) }
          )
        )
        .toggleStyle(.switch)
      }

      if sharing.wantsPublicSharing {
        publicActivityRow
      }
    }
  }

  // MARK: - Live community-pool activity counter
  //
  // Pure local readout of `WebSocketClient.communityTasksProcessed`
  // and `lastTaskAt`. The counter only ticks for tasks where the
  // requester was someone OTHER than this device's owner — set on the
  // wire by the worker via `requester_is_owner: false`. Self-served
  // tasks are deliberately excluded so "served this session" can't
  // over-report the community contribution. TimelineView re-renders
  // the relative time every minute without a hand-rolled timer.

  private var publicActivityRow: some View {
    TimelineView(.periodic(from: .now, by: 60)) { context in
      HStack(spacing: 6) {
        Circle()
          .fill(.green)
          .frame(width: 6, height: 6)
        Text(
          String(
            localized:
              "\(sharing.cloudCommunityTasksProcessed) community request(s) served this session"
          ))
          .font(.caption)
          .foregroundStyle(.secondary)
        if let last = sharing.cloudLastTaskAt,
          sharing.cloudCommunityTasksProcessed > 0
        {
          Text("·").font(.caption).foregroundStyle(.tertiary)
          Text(last, format: .relative(presentation: .named, unitsStyle: .narrow))
            .font(.caption)
            .foregroundStyle(.secondary)
            .id(context.date)
        }
        Spacer()
      }
      .padding(.top, 4)
    }
  }

  @ViewBuilder
  private var cloudConnectionStatus: some View {
    switch sharing.cloudConnectionState {
    case .disconnected:
      StatusRow(
        icon: "circle",
        iconColor: .secondary,
        title: "Disconnected",
        subtitle: "Waiting for network..."
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
        subtitle: "Ready to process requests"
      )

      Divider()

      VStack(alignment: .leading, spacing: 12) {
        InfoRow(label: "Device", value: DeviceInfo.deviceName)
        InfoRow(label: "Chip", value: DeviceInfo.chipModel)
        InfoRow(label: "Memory", value: DeviceInfo.formattedMemory)
      }

      Divider()

      HStack(spacing: 40) {
        StatCard(
          title: "Logs Processed", value: "\(sharing.cloudLogsProcessed)",
          compact: true)
        StatCard(
          title: "Hardware ID", value: String(DeviceInfo.hardwareID.prefix(8)),
          compact: true)
      }

    case .reconnecting(let attempt, let nextRetryIn):
      VStack(alignment: .leading, spacing: 12) {
        StatusRow(
          isLoading: true,
          title: "Reconnecting...",
          subtitle: "Attempt \(attempt), next retry in \(Int(nextRetryIn))s"
        )

        Button(String(localized: "Retry Now")) {
          sharing.retryCloudConnection()
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
      }

    case .failed(let error):
      VStack(alignment: .leading, spacing: 12) {
        StatusRow(
          icon: "exclamationmark.triangle.fill",
          iconColor: .orange,
          title: "Connection Failed",
          subtitle: LocalizedStringKey(error.localizedDescription)
        )

        Button(String(localized: "Retry")) {
          sharing.retryCloudConnection()
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
      }
    }
  }

  // MARK: - Share Locally Card

  @State private var portText = ""

  private var isLocalStarting: Bool {
    sharing.wantsLocalSharing && !sharing.isLocalActive
      && !sharing.localPortConflict && sharing.localError == nil
  }

  private var portNeedsApply: Bool {
    guard let port = UInt16(portText) else { return false }
    return port != sharing.localPort
  }

  private var localShareCard: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        VStack(alignment: .leading, spacing: 4) {
          Text(String(localized: "Share Locally"))
            .font(.headline)
          Text(String(localized: "Standard Chat Completion API for local apps"))
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Spacer()

        if isLocalStarting {
          ProgressView()
            .controlSize(.small)
        } else {
          Toggle(
            "",
            isOn: Binding(
              get: { sharing.isLocalActive },
              set: { sharing.setLocalSharing($0) }
            )
          )
          .toggleStyle(.switch)
        }
      }

      if sharing.wantsLocalSharing {
        Divider()

        localStatusSection

        portConfigRow

        if sharing.isLocalActive {
          Divider()

          VStack(alignment: .leading, spacing: 12) {
            InfoRow(label: "Model", value: AppIdentity.modelName)
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
            StatCard(
              title: "Requests Served", value: "\(sharing.localRequestCount)",
              compact: true)
          }
        }
      }
    }
    .padding()
    .frame(maxWidth: .infinity, alignment: .leading)
    .glassEffect(in: .rect(cornerRadius: 12, style: .continuous))
    .task { portText = String(sharing.localPort) }
    .onChange(of: sharing.localPortConflict) { _, isConflict in
      if isConflict, let suggested = sharing.localSuggestedPort {
        portText = String(suggested)
      }
    }
  }

  @ViewBuilder
  private var localStatusSection: some View {
    if sharing.localPortConflict {
      StatusRow(
        icon: "exclamationmark.triangle.fill",
        iconColor: .orange,
        title: "Port Conflict",
        subtitle: "Port \(sharing.localPort) is already in use"
      )
    } else if isLocalStarting {
      StatusRow(
        isLoading: true,
        title: "Starting...",
        subtitle: "Port \(sharing.localPort)"
      )
    } else if sharing.isLocalActive {
      StatusRow(
        icon: "checkmark.circle.fill",
        iconColor: .green,
        title: "Running",
        subtitle: "Port \(sharing.localPort)"
      )
    } else if let error = sharing.localError {
      StatusRow(
        icon: "exclamationmark.triangle.fill",
        iconColor: .red,
        title: "Failed to Start",
        subtitle: LocalizedStringKey(error.localizedDescription)
      )
    }
  }

  private var portConfigRow: some View {
    HStack(spacing: 8) {
      Text(String(localized: "Port"))
        .font(.caption)
        .foregroundStyle(.secondary)

      TextField("", text: $portText)
        .font(.system(.caption, design: .monospaced))
        .multilineTextAlignment(.center)
        .frame(width: 64)
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 6))
        #if os(iOS)
          .keyboardType(.numberPad)
        #endif

      if portNeedsApply, let port = UInt16(portText) {
        if APIServer.isPortAvailable(port) {
          Image(systemName: "checkmark.circle.fill")
            .font(.caption2)
            .foregroundStyle(.green)
        } else {
          Image(systemName: "xmark.circle.fill")
            .font(.caption2)
            .foregroundStyle(.red)
        }
      }

      Spacer()

      if portNeedsApply {
        Button(String(localized: "Apply")) {
          guard let port = UInt16(portText) else { return }
          sharing.setLocalPort(port)
        }
        .font(.caption)
        .buttonStyle(.borderedProminent)
        .controlSize(.mini)
        .disabled(UInt16(portText).map { !APIServer.isPortAvailable($0) } ?? true)
      }
    }
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

      Text("Both sharing modes require Apple's built-in AI to function.")
        .font(.subheadline)
        .foregroundStyle(.secondary)

      Divider()

      statusContent
    }
    .padding()
    .frame(maxWidth: .infinity, alignment: .leading)
    .glassEffect(in: .rect(cornerRadius: 12, style: .continuous))
  }

  private var headerIcon: String { availability.statusIcon }
  private var headerColor: Color { availability.statusColor }
  private var headerTitle: String { availability.statusTitle }

  @ViewBuilder
  private var statusContent: some View {
    switch availability {
    case .available:
      EmptyView()

    case .unavailable(.deviceNotEligible):
      VStack(alignment: .leading, spacing: 12) {
        Text("This device doesn't support Apple's built-in AI. Compatible devices include:")
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

private struct StatusRow: View {
  var icon: String?
  var iconColor: Color = .secondary
  var isLoading: Bool = false
  let title: LocalizedStringKey
  let subtitle: LocalizedStringKey

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

private struct InfoRow: View {
  let label: LocalizedStringKey
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

private struct EndpointRow: View {
  let label: LocalizedStringKey
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
        Clipboard.copy(url)
      } label: {
        Image(systemName: "doc.on.doc")
          .font(.caption)
          .foregroundStyle(.blue)
      }
      .buttonStyle(.plain)
      .help("Copy URL")
    }
  }
}

#Preview {
  LocalDeviceView()
    .environment(SharingManager())
}
