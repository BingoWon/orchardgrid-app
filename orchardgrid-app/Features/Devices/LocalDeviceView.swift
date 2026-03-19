import FoundationModels
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

            capabilitiesCard
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
        StatCard(title: "Tasks Processed", value: "\(sharing.cloudTasksProcessed)", compact: true)
        StatCard(
          title: "Hardware ID", value: String(DeviceInfo.hardwareID.prefix(8)), compact: true)
      }

    case .reconnecting(let attempt, let nextRetryIn):
      VStack(alignment: .leading, spacing: 12) {
        StatusRow(
          isLoading: true,
          title: "Reconnecting...",
          subtitle: "Attempt \(attempt), next retry in \(Int(nextRetryIn))s"
        )

        Button("Retry Now") {
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

  @State private var portText = ""

  private var isLocalStarting: Bool {
    sharing.wantsLocalSharing && !sharing.isLocalActive
      && !sharing.localPortConflict && sharing.localErrorMessage == nil
  }

  private var portNeedsApply: Bool {
    guard let port = UInt16(portText) else { return false }
    return port != sharing.localPort
  }

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
            StatCard(title: "Requests Served", value: "\(sharing.localRequestCount)", compact: true)
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
    } else if let error = sharing.localErrorMessage {
      StatusRow(
        icon: "exclamationmark.triangle.fill",
        iconColor: .red,
        title: "Failed to Start",
        subtitle: error
      )
    }
  }

  private var portConfigRow: some View {
    HStack(spacing: 8) {
      Text("Port")
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
        Button("Apply") {
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
  // MARK: - Shared Capabilities Card

  private var capabilitiesCard: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        VStack(alignment: .leading, spacing: 4) {
          Text("Shared Capabilities")
            .font(.headline)
          Text("Choose which AI features this device shares")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
      }

      Divider()

      VStack(spacing: 0) {
        ForEach(Capability.allCases, id: \.self) { capability in
          CapabilityRow(
            capability: capability,
            isEnabled: sharing.isCapabilityEnabled(capability),
            isAvailable: sharing.isCapabilityAvailable(capability),
            unavailabilityReason: sharing.capabilityUnavailabilityReason(capability),
            needsSettingsRedirect: sharing.capabilityNeedsSettingsRedirect(capability)
          ) { enabled in
            sharing.setCapabilityEnabled(capability, enabled: enabled)
          }

          if capability != Capability.allCases.last {
            Divider()
              .padding(.leading, 40)
          }
        }
      }
    }
    .padding()
    .frame(maxWidth: .infinity, alignment: .leading)
    .glassEffect(in: .rect(cornerRadius: 12, style: .continuous))
  }
}

// MARK: - Capability Row

private struct CapabilityRow: View {
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
          Text("Unavailable")
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
        Label("Open Settings", systemImage: "gear")
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
        Label("Open System Settings", systemImage: "gear")
          .font(.caption2)
      }
      .buttonStyle(.bordered)
      .controlSize(.mini)
    #endif
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

private struct StatusRow: View {
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

private struct InfoRow: View {
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

private struct EndpointRow: View {
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
