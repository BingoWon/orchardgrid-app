import FoundationModels
import SwiftUI
#if os(macOS)
  import AppKit
#elseif os(iOS)
  import UIKit
#endif

struct LocalDeviceView: View {
  @Environment(WebSocketClient.self) private var wsClient
  @Environment(APIServer.self) private var apiServer

  var body: some View {
    ScrollView {
      GlassEffectContainer {
        VStack(alignment: .leading, spacing: 24) {
          // Platform Connection Card
          platformConnectionCard

          // API Server Card
          apiServerCard
        }
        .padding()
      }
    }
    .navigationTitle(DeviceInfo.deviceName)
  }

  // MARK: - Platform Connection Card

  private var platformConnectionCard: some View {
    VStack(alignment: .leading, spacing: 16) {
      // Header with Toggle
      HStack {
        VStack(alignment: .leading, spacing: 4) {
          Text("Platform Connection")
            .font(.headline)
          Text("Share computing power with OrchardGrid")
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Spacer()

        Toggle("", isOn: Binding(
          get: { wsClient.isEnabled },
          set: { wsClient.isEnabled = $0 }
        ))
        .toggleStyle(.switch)
        .disabled(!wsClient.canEnable)
      }

      // Content based on model availability
      switch wsClient.modelAvailability {
      case .available:
        if wsClient.isEnabled {
          Divider()
          availableContent
        }

      case .unavailable(.deviceNotEligible):
        Divider()
        DeviceNotEligibleView()

      case .unavailable(.appleIntelligenceNotEnabled):
        Divider()
        AppleIntelligenceNotEnabledView()

      case .unavailable(.modelNotReady):
        Divider()
        ModelNotReadyView()

      case .unavailable:
        Divider()
        ModelUnavailableView()
      }
    }
    .padding()
    .glassEffect(in: .rect(cornerRadius: 12, style: .continuous))
  }

  // MARK: - API Server Card

  private var apiServerCard: some View {
    VStack(alignment: .leading, spacing: 16) {
      // Header with Toggle
      HStack {
        VStack(alignment: .leading, spacing: 4) {
          Text("Local API Server")
            .font(.headline)
          Text("OpenAI-compatible API for local development")
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Spacer()

        Toggle("", isOn: Binding(
          get: { apiServer.isEnabled },
          set: { apiServer.isEnabled = $0 }
        ))
        .toggleStyle(.switch)
      }

      // Status and Information
      if apiServer.isEnabled {
        Divider()

        HStack {
          Image(systemName: apiServer.isRunning ? "checkmark.circle.fill" : "hourglass.circle.fill")
            .foregroundStyle(apiServer.isRunning ? .green : .orange)

          VStack(alignment: .leading, spacing: 2) {
            Text(apiServer.isRunning ? "Running" : "Starting...")
              .font(.subheadline)
              .fontWeight(.medium)
            Text("Port \(apiServer.port)")
              .font(.caption)
              .foregroundStyle(.secondary)
          }

          Spacer()
        }

        if apiServer.isRunning {
          Divider()

          VStack(alignment: .leading, spacing: 12) {
            // Model
            HStack(alignment: .top, spacing: 8) {
              Text("Model")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)

              Text("apple-intelligence")
                .font(.caption)
                .fontWeight(.medium)
                .textSelection(.enabled)

              Spacer()
            }

            // Local Endpoint
            EndpointRow(
              label: "Local",
              url: "http://localhost:\(apiServer.port)/v1/chat/completions"
            )

            // Network Endpoint (if available)
            if let localIP = apiServer.localIPAddress {
              EndpointRow(
                label: "Network",
                url: "http://\(localIP):\(apiServer.port)/v1/chat/completions"
              )
            }
          }

          Divider()

          HStack(spacing: 40) {
            StatView(title: "Requests Served", value: "\(apiServer.requestCount)")
          }
        }
      }
    }
    .padding()
    .glassEffect(in: .rect(cornerRadius: 12, style: .continuous))
  }

  @ViewBuilder
  private var availableContent: some View {
    switch wsClient.connectionState {
    case .disconnected:
      HStack {
        Image(systemName: "circle")
          .foregroundStyle(.secondary)

        VStack(alignment: .leading, spacing: 2) {
          Text("Disconnected")
            .font(.subheadline)
            .fontWeight(.medium)
          Text("Enable to start connecting")
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Spacer()
      }

    case .connecting:
      HStack {
        ProgressView()
          .controlSize(.small)

        VStack(alignment: .leading, spacing: 2) {
          Text("Connecting...")
            .font(.subheadline)
            .fontWeight(.medium)
          Text("Establishing connection")
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Spacer()
      }

    case .connected:
      HStack {
        Image(systemName: "checkmark.circle.fill")
          .foregroundStyle(.green)

        VStack(alignment: .leading, spacing: 2) {
          Text("Connected")
            .font(.subheadline)
            .fontWeight(.medium)
          Text("Ready to process tasks")
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Spacer()
      }

      Divider()

      // Device Information
      VStack(alignment: .leading, spacing: 12) {
        InfoRow(label: "Device", value: DeviceInfo.deviceName)
        InfoRow(label: "Chip", value: DeviceInfo.chipModel)
        InfoRow(label: "Memory", value: DeviceInfo.formattedMemory)
      }

      Divider()

      HStack(spacing: 40) {
        StatView(title: "Tasks Processed", value: "\(wsClient.tasksProcessed)")
        StatView(title: "Device ID", value: String(DeviceID.current.prefix(8)))
      }

    case let .reconnecting(attempt, nextRetryIn):
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          ProgressView()
            .controlSize(.small)

          VStack(alignment: .leading, spacing: 2) {
            Text("Reconnecting...")
              .font(.subheadline)
              .fontWeight(.medium)
            if let nextRetryIn {
              Text("Attempt \(attempt), next retry in \(Int(nextRetryIn))s")
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
              Text("Attempt \(attempt)")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }

          Spacer()
        }

        Button("Retry Now") {
          wsClient.retry()
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
      }

    case let .failed(error):
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(.orange)

          VStack(alignment: .leading, spacing: 2) {
            Text("Connection Failed")
              .font(.subheadline)
              .fontWeight(.medium)
            Text(error)
              .font(.caption)
              .foregroundStyle(.secondary)
          }

          Spacer()
        }

        Button("Retry") {
          wsClient.retry()
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
      }
    }
  }
}

// MARK: - Availability Status Views

struct DeviceNotEligibleView: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundStyle(.orange)
        Text("Device Not Supported")
          .font(.subheadline)
          .fontWeight(.medium)
      }

      Text("Your device doesn't support Apple Intelligence. Platform Connection requires:")
        .font(.caption)
        .foregroundStyle(.secondary)

      VStack(alignment: .leading, spacing: 4) {
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
  }
}

struct AppleIntelligenceNotEnabledView: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundStyle(.orange)
        Text("Apple Intelligence Not Enabled")
          .font(.subheadline)
          .fontWeight(.medium)
      }

      Text("To share computing power, you need to enable Apple Intelligence in Settings.")
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
  }
}

struct ModelNotReadyView: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        ProgressView()
          .controlSize(.small)
        Text("Apple Intelligence Downloading...")
          .font(.subheadline)
          .fontWeight(.medium)
      }

      Text("The on-device model is being downloaded. This may take a while.")
        .font(.caption)
        .foregroundStyle(.secondary)

      Text("Platform Connection will be available once the download completes.")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }
}

struct ModelUnavailableView: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundStyle(.orange)
        Text("Apple Intelligence Unavailable")
          .font(.subheadline)
          .fontWeight(.medium)
      }

      Text("The on-device model is currently unavailable for an unknown reason.")
        .font(.caption)
        .foregroundStyle(.secondary)

      Text("Please try again later or contact support if the issue persists.")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }
}

// MARK: - Supporting Views

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

      VStack(alignment: .leading, spacing: 4) {
        Text(url)
          .font(.caption)
          .fontWeight(.medium)
          .textSelection(.enabled)
          .lineLimit(2)
          .fixedSize(horizontal: false, vertical: true)
      }

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
    .environment(WebSocketClient())
    .environment(APIServer())
}
