import SwiftUI

struct AllDevicesView: View {
  @Environment(DevicesManager.self) private var devicesManager
  @Environment(AuthManager.self) private var authManager

  var body: some View {
    ScrollView {
      GlassEffectContainer {
        VStack(alignment: .leading, spacing: 24) {
          // Summary Card
          VStack(alignment: .leading, spacing: 12) {
            Text("Summary")
              .font(.headline)
              .foregroundStyle(.secondary)

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
          }
          .padding()
          .glassEffect(in: .rect(cornerRadius: 12))

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
          if devicesManager.devices.isEmpty, !devicesManager.isInitialLoading {
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
            .glassEffect(in: .rect(cornerRadius: 12))
          }
        }
        .padding()
      }
    }
    .navigationTitle("All Devices")
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button {
          Task {
            if let token = authManager.authToken {
              await devicesManager.fetchDevices(authToken: token, isManualRefresh: true)
            }
          }
        } label: {
          Image(systemName: "arrow.clockwise")
            .rotationEffect(.degrees(devicesManager.isRefreshing ? 360 : 0))
            .animation(
              devicesManager.isRefreshing
                ? .linear(duration: 1).repeatForever(autoreverses: false)
                : .default,
              value: devicesManager.isRefreshing
            )
        }
        .disabled(devicesManager.isRefreshing)
      }
    }
    .task {
      guard let token = authManager.authToken else {
        Logger.error(.devices, "No auth token available")
        return
      }

      // Initial fetch
      Logger.log(.devices, "Fetching devices with token")
      await devicesManager.fetchDevices(authToken: token)

      // Auto-refresh in background (no loading indicator)
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(DeviceConfig.deviceListRefreshInterval))
        guard !Task.isCancelled else { break }
        await devicesManager.fetchDevices(authToken: token, isManualRefresh: false)
      }
    }
    .overlay {
      // Only show loading on initial load
      if devicesManager.isInitialLoading {
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
    HStack(spacing: 16) {
      // Icon
      Image(systemName: device.platformIcon)
        .font(.system(size: 32))
        .foregroundStyle(.blue)
        .frame(width: 48, height: 48)

      // Info
      VStack(alignment: .leading, spacing: 4) {
        // Device name
        if let deviceName = device.deviceName {
          Text(deviceName)
            .font(.headline)
        }

        // Platform and OS version
        HStack(spacing: 4) {
          Text(device.platform)
            .font(device.deviceName != nil ? .subheadline : .headline)
            .foregroundStyle(device.deviceName != nil ? .secondary : .primary)

          if let osVersion = device.osVersion {
            Text("•")
              .font(.caption)
              .foregroundStyle(.secondary)
            Text(osVersion)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }

        // Chip model and memory
        HStack(spacing: 4) {
          if let chipModel = device.chipModel {
            Text(chipModel)
              .font(.caption)
              .foregroundStyle(.secondary)
          }

          if device.chipModel != nil, device.memoryGb != nil {
            Text("•")
              .font(.caption)
              .foregroundStyle(.secondary)
          }

          if let memoryGb = device.memoryGb {
            Text("\(Int(memoryGb)) GB")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }

        // Status and last seen
        HStack(spacing: 8) {
          Circle()
            .fill(statusColor)
            .frame(width: 8, height: 8)

          Text(device.statusText)
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
    .glassEffect(in: .rect(cornerRadius: 12))
  }

  private var statusColor: Color {
    device.statusColor == "green" ? .green : .gray
  }
}

#Preview {
  AllDevicesView()
    .environment(DevicesManager())
    .environment(AuthManager())
}
