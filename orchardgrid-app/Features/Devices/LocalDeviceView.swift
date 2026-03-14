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
        StatView(title: "Tasks Processed", value: "\(sharing.cloudTasksProcessed)")
        StatView(title: "Hardware ID", value: String(DeviceInfo.hardwareID.prefix(8)))
      }

    case let .reconnecting(attempt, nextRetryIn):
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

  @State private var portInput = ""

  private var isLocalStarting: Bool {
    sharing.wantsLocalSharing && !sharing.isLocalActive
      && !sharing.localPortConflict && sharing.localErrorMessage == nil
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
          Toggle("", isOn: Binding(
            get: { sharing.isLocalActive },
            set: { sharing.setLocalSharing($0) }
          ))
          .toggleStyle(.switch)
        }
      }

      if sharing.wantsLocalSharing {
        Divider()

        if sharing.localPortConflict {
          portConflictSection
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
        } else if let error = sharing.localErrorMessage {
          StatusRow(
            icon: "exclamationmark.triangle.fill",
            iconColor: .red,
            title: "Failed to Start",
            subtitle: error
          )
        }
      }
    }
    .padding()
    .frame(maxWidth: .infinity, alignment: .leading)
    .glassEffect(in: .rect(cornerRadius: 12, style: .continuous))
  }

  private var portConflictSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 8) {
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundStyle(.orange)
        Text("Port \(sharing.localPort) is already in use")
          .font(.subheadline)
          .fontWeight(.medium)
      }

      HStack(spacing: 12) {
        HStack {
          Text("Port")
            .font(.subheadline)
            .foregroundStyle(.secondary)
          TextField("Port", text: $portInput)
            .textFieldStyle(.roundedBorder)
            .frame(width: 80)
            #if os(iOS)
              .keyboardType(.numberPad)
            #endif
        }

        if let p = UInt16(portInput), APIServer.isPortAvailable(p) {
          Label("Available", systemImage: "checkmark.circle.fill")
            .font(.caption)
            .foregroundStyle(.green)
        } else if !portInput.isEmpty {
          Label("In use", systemImage: "xmark.circle.fill")
            .font(.caption)
            .foregroundStyle(.red)
        }

        Spacer()

        Button("Start") {
          if let p = UInt16(portInput) {
            sharing.setLocalPort(p)
          }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .disabled(UInt16(portInput).map { !APIServer.isPortAvailable($0) } ?? true)
      }
    }
    .onAppear {
      portInput = sharing.localSuggestedPort.map(String.init) ?? String(sharing.localPort &+ 1)
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

        Toggle("", isOn: Binding(
          get: { isEnabled && isAvailable },
          set: { onToggle($0) }
        ))
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
