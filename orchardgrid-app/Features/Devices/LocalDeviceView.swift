import SwiftUI
import FoundationModels

struct LocalDeviceView: View {
  @Environment(WebSocketClient.self) private var wsClient
  @Environment(APIServer.self) private var apiServer

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        // Platform Connection Card
        GroupBox {
          VStack(alignment: .leading, spacing: 16) {
            // Toggle Row
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

            case .unavailable(_):
              Divider()
              ModelUnavailableView()
            }
          }
          .padding()
        }

        // API Server Card
        GroupBox {
          VStack(alignment: .leading, spacing: 16) {
            // Toggle Row
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

            // Status Row
            if apiServer.isEnabled {
              Divider()

              HStack {
                Image(systemName: apiServer
                  .isRunning ? "checkmark.circle.fill" : "hourglass.circle.fill")
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

              // Stats Row
              if apiServer.isRunning {
                Divider()

                HStack(spacing: 40) {
                  StatView(title: "Requests Served", value: "\(apiServer.requestCount)")
                  StatView(title: "Endpoint", value: "localhost:\(apiServer.port)")
                }
              }
            }
          }
          .padding()
        }
      }
      .padding()
    }
    .navigationTitle("This Mac")
  }

  @ViewBuilder
  private var availableContent: some View {
    if wsClient.isConnected {
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

      HStack(spacing: 40) {
        StatView(title: "Tasks Processed", value: "\(wsClient.tasksProcessed)")
        StatView(title: "Device ID", value: String(DeviceID.current.prefix(8)))
      }
    } else if let error = wsClient.lastError {
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
    } else {
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

      Link("Learn More", destination: URL(string: "https://support.apple.com/apple-intelligence")!)
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
