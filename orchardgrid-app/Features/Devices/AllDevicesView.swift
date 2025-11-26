import SwiftUI

struct AllDevicesView: View {
  @Environment(DevicesManager.self) private var devicesManager
  @Environment(AuthManager.self) private var authManager
  @Environment(ObserverClient.self) private var observerClient
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
        VStack(alignment: .leading, spacing: Constants.standardSpacing) {
          // Local Device Quick Control (always visible)
          // Wide layout: QuickControl + Summary side by side
          // Compact layout: QuickControl + Summary stacked
          if authManager.isAuthenticated {
            // Connection Status & Last Updated (only when authenticated)
            HStack {
              HStack(spacing: 4) {
                Circle()
                  .fill(observerClient.status == .connected ? .green : .gray)
                  .frame(width: 6, height: 6)
                Text(observerClient.status == .connected ? "Live" : "Offline")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }

              Spacer()

              LastUpdatedView(lastUpdatedText: devicesManager.lastUpdatedText)
            }

            if isWideLayout {
              HStack(alignment: .top, spacing: 16) {
                LocalDeviceQuickControl()
                summaryCard
              }
            } else {
              LocalDeviceQuickControl()
              summaryCard
            }

            // Device List
            if !devicesManager.devices.isEmpty {
              if isWideLayout {
                deviceTableSection
              } else {
                deviceCardSections
              }
            }

            // Empty State
            if devicesManager.devices.isEmpty, !devicesManager.isInitialLoading {
              emptyState
            }

            // Error State
            if let error = devicesManager.lastError {
              errorState(error: error)
            }
          } else {
            // Guest Mode: Show QuickControl + Guest Prompt
            LocalDeviceQuickControl()

            GuestFeaturePrompt(
              icon: "server.rack",
              title: "See All Your Devices",
              description: "Sign in to view and manage devices across all your Apple devices.",
              benefits: [
                "Track contributions from each device",
                "View processing statistics",
                "Real-time status updates",
              ],
              buttonTitle: "Sign In to View Devices"
            )
          }
        }
        .padding(Constants.standardPadding)
      }
    }
    .refreshable {
      if let token = authManager.authToken {
        await devicesManager.fetchDevices(authToken: token, isManualRefresh: true)
      }
    }
    .navigationTitle("Devices")
    .toolbarRole(.editor)
    .toolbarTitleDisplayMode(.inlineLarge)
    .withPlatformToolbar {
      if authManager.isAuthenticated {
        refreshButton
      }
    }
    .task {
      if let token = authManager.authToken {
        await devicesManager.fetchDevices(authToken: token)
      }
    }
  }

  // MARK: - Summary Card

  private var summaryCard: some View {
    VStack(alignment: .leading, spacing: Constants.summaryCardSpacing) {
      Text("Summary")
        .font(.headline)
        .foregroundStyle(.secondary)

      HStack(spacing: 16) {
        SummaryStatCard(title: "Total", value: "\(devicesManager.devices.count)")
        SummaryStatCard(title: "Online", value: "\(devicesManager.onlineDevices.count)")
        SummaryStatCard(title: "Tasks", value: "\(devicesManager.totalTasksProcessed)")
      }
    }
    .padding(Constants.standardPadding)
    .frame(maxWidth: .infinity, alignment: .leading)
    .glassEffect(in: .rect(cornerRadius: Constants.cornerRadius, style: .continuous))
  }

  // MARK: - Device Table Section (Wide Layout)

  private var deviceTableSection: some View {
    VStack(alignment: .leading, spacing: Constants.summaryCardSpacing) {
      Text("All Devices")
        .font(.headline)
        .foregroundStyle(.secondary)

      DeviceTableView(devices: devicesManager.devices)
        .frame(minHeight: 200)
    }
    .padding(Constants.standardPadding)
    .glassEffect(in: .rect(cornerRadius: Constants.cornerRadius, style: .continuous))
  }

  // MARK: - Device Card Sections (Compact Layout)

  @ViewBuilder
  private var deviceCardSections: some View {
    if !devicesManager.onlineDevices.isEmpty {
      deviceSection(title: "Online Devices", devices: devicesManager.onlineDevices)
    }

    if !devicesManager.offlineDevices.isEmpty {
      deviceSection(title: "Offline Devices", devices: devicesManager.offlineDevices)
    }
  }

  private func deviceSection(title: String, devices: [Device]) -> some View {
    VStack(alignment: .leading, spacing: Constants.summaryCardSpacing) {
      Text(title)
        .font(.headline)
        .foregroundStyle(.secondary)

      ForEach(devices) { device in
        DeviceCard(device: device)
      }
    }
  }

  // MARK: - Empty State

  private var emptyState: some View {
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

  // MARK: - Error State

  private func errorState(error: String) -> some View {
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
      .buttonStyle(.glass)
    }
    .padding()
    .glassEffect(in: .rect(cornerRadius: 12, style: .continuous))
  }

  // MARK: - Refresh Button

  private var refreshButton: some View {
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

// MARK: - Device Card

struct DeviceCard: View {
  let device: Device

  var body: some View {
    HStack(spacing: 12) {
      // Icon
      Image(systemName: device.platformIcon)
        .font(.system(size: 28))
        .foregroundStyle(.blue)
        .frame(width: 40, height: 40)

      // Info - 2 lines
      VStack(alignment: .leading, spacing: 6) {
        // Line 1: Flag + Device name
        HStack(spacing: 6) {
          if !device.flagEmoji.isEmpty {
            Text(device.flagEmoji)
          }
          Text(device.deviceName ?? device.platform)
            .fontWeight(.medium)
        }
        .font(.subheadline)

        // Line 2: Platform · OS · Chip · Memory
        HStack(spacing: 0) {
          Text(device.platform)
          if let osVersion = device.shortOSVersion {
            Text(" \(osVersion)")
          }
          if device.chipModel != nil || device.memoryGb != nil {
            Text(" · ")
          }
          if let chipModel = device.chipModel {
            Text(chipModel)
          }
          if let memoryGb = device.memoryGb {
            Text(" \(Int(memoryGb)) GB")
          }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)

        // Line 3: Status indicator + time
        HStack(spacing: 6) {
          Circle()
            .fill(statusColor)
            .frame(width: 6, height: 6)
          Text(device.statusText)
          Text("·")
          Text(device.lastSeenText)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
      }

      Spacer()

      // Tasks count - centered
      VStack(spacing: 2) {
        Text("\(device.tasksProcessed)")
          .font(.title3)
          .fontWeight(.semibold)
        Text("tasks")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
      .frame(minWidth: 50)
    }
    .padding(12)
    .glassEffect(in: .rect(cornerRadius: 12, style: .continuous))
  }

  private var statusColor: Color {
    device.statusColor == "green" ? .green : .gray
  }
}

// MARK: - Summary Stat Card

private struct SummaryStatCard: View {
  let title: String
  let value: String

  var body: some View {
    VStack(spacing: 4) {
      Text(value)
        .font(.title2.bold())

      Text(title)
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 12)
    .background(.ultraThinMaterial, in: .rect(cornerRadius: 10))
  }
}

#Preview {
  AllDevicesView()
    .environment(DevicesManager())
    .environment(AuthManager())
    .environment(ObserverClient())
    .environment(WebSocketClient())
    .environment(APIServer())
    .environment(NavigationState())
}
