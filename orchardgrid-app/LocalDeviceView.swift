import SwiftUI

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
            }

            // Status Row (always show when enabled)
            if wsClient.isEnabled {
              Divider()

              // Success State
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
              }
              // Error State
              else if let error = wsClient.lastError {
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
              // Connecting State
              else {
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
