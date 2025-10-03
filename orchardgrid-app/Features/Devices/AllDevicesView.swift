import SwiftUI

struct AllDevicesView: View {
  @Environment(DevicesManager.self) private var devicesManager
  @Environment(AuthManager.self) private var authManager

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        // Summary Card
        GroupBox("Summary") {
          HStack(spacing: 40) {
            StatView(
              title: "Total Devices",
              value: "\(devicesManager.devices.count)"
            )
            StatView(
              title: "Online",
              value: "\(devicesManager.onlineDevices.count)"
            )
            StatView(
              title: "Total Tasks",
              value: "\(devicesManager.totalTasksProcessed)"
            )
          }
          .padding()
        }

        // Online Devices
        if !devicesManager.onlineDevices.isEmpty {
          VStack(alignment: .leading, spacing: 12) {
            Text("Online Devices")
              .font(.headline)
              .foregroundStyle(.secondary)

            ForEach(devicesManager.onlineDevices) { device in
              DeviceCard(device: device)
            }
          }
        }

        // Offline Devices
        if !devicesManager.offlineDevices.isEmpty {
          VStack(alignment: .leading, spacing: 12) {
            Text("Offline Devices")
              .font(.headline)
              .foregroundStyle(.secondary)

            ForEach(devicesManager.offlineDevices) { device in
              DeviceCard(device: device)
            }
          }
        }

        // Empty State
        if devicesManager.devices.isEmpty, !devicesManager.isLoading {
          VStack(spacing: 16) {
            Image(systemName: "server.rack")
              .font(.system(size: 48))
              .foregroundStyle(.secondary)

            Text("No Devices")
              .font(.title2)
              .fontWeight(.semibold)

            Text("Connect a device to get started")
              .font(.subheadline)
              .foregroundStyle(.secondary)
          }
          .frame(maxWidth: .infinity)
          .padding(.vertical, 60)
        }

        // Error State
        if let error = devicesManager.lastError {
          GroupBox {
            HStack {
              Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)

              Text(error)
                .font(.subheadline)

              Spacer()

              Button("Retry") {
                Task {
                  if let token = authManager.authToken {
                    await devicesManager.fetchDevices(authToken: token)
                  }
                }
              }
            }
            .padding()
          }
        }
      }
      .padding()
    }
    .navigationTitle("All Devices")
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button {
          Task {
            if let token = authManager.authToken {
              await devicesManager.fetchDevices(authToken: token)
            }
          }
        } label: {
          Image(systemName: "arrow.clockwise")
        }
        .disabled(devicesManager.isLoading)
      }
    }
    .task {
      if let token = authManager.authToken {
        Logger.log(.devices, "Fetching devices with token")
        await devicesManager.fetchDevices(authToken: token)
      } else {
        Logger.error(.devices, "No auth token available")
      }
    }
    .overlay {
      if devicesManager.isLoading {
        ProgressView()
          .scaleEffect(1.5)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .background(.ultraThinMaterial)
      }
    }
  }
}

// MARK: - Device Card

struct DeviceCard: View {
  let device: Device

  var body: some View {
    GroupBox {
      HStack(spacing: 16) {
        // Icon
        Image(systemName: device.platformIcon)
          .font(.system(size: 32))
          .foregroundStyle(.blue)
          .frame(width: 48, height: 48)

        // Info
        VStack(alignment: .leading, spacing: 4) {
          Text(device.platform.capitalized)
            .font(.headline)

          if let osVersion = device.osVersion {
            Text(osVersion)
              .font(.subheadline)
              .foregroundStyle(.secondary)
          }

          HStack(spacing: 8) {
            Circle()
              .fill(statusColor)
              .frame(width: 8, height: 8)

            Text(device.status.capitalized)
              .font(.caption)
              .foregroundStyle(.secondary)

            Text("•")
              .foregroundStyle(.secondary)

            Text(device.lastSeenText)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }

        Spacer()

        // Stats
        VStack(alignment: .trailing, spacing: 4) {
          Text("\(device.tasksProcessed)")
            .font(.title2)
            .fontWeight(.semibold)

          Text("tasks")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      .padding()
    }
  }

  private var statusColor: Color {
    switch device.statusColor {
    case "green": .green
    case "orange": .orange
    case "gray": .gray
    default: .gray
    }
  }
}

#Preview {
  AllDevicesView()
    .environment(DevicesManager())
    .environment(AuthManager())
}
