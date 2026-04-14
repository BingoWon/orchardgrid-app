import SwiftUI

struct AllDevicesView: View {
  @Environment(DevicesManager.self) private var devicesManager
  @Environment(AuthManager.self) private var authManager
  @Environment(ObserverClient.self) private var observerClient
  @Environment(\.isWideLayout) private var isWideLayout

  var body: some View {
    ScrollView {
      GlassEffectContainer(spacing: Constants.standardSpacing) {
        VStack(alignment: .leading, spacing: Constants.standardSpacing) {
          // Local Device Quick Control (always visible)
          // Wide layout: QuickControl + Summary side by side
          // Compact layout: QuickControl + Summary stacked
          if authManager.isAuthenticated {
            HStack {
              ConnectionStatusBadge(isConnected: observerClient.status == .connected)
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

            if let error = devicesManager.lastError {
              ErrorBanner(error: error) {
                Task { await devicesManager.fetchDevices() }
              }
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
      await devicesManager.fetchDevices(isManualRefresh: true)
    }
    .navigationTitle(String(localized: "Devices"))
    .toolbarRole(.editor)
    .toolbarTitleDisplayMode(.inlineLarge)
    .contentToolbar {
      if authManager.isAuthenticated {
        refreshButton
      }
    }
    .task(id: authManager.userId) {
      await devicesManager.fetchDevices()
    }
  }

  // MARK: - Summary Card

  private var summaryCard: some View {
    VStack(alignment: .leading, spacing: Constants.summaryCardSpacing) {
      Text(String(localized: "Summary"))
        .font(.headline)
        .foregroundStyle(.secondary)

      HStack(spacing: 16) {
        StatCard(title: "Total", value: "\(devicesManager.devices.count)")
        StatCard(title: "Online", value: "\(devicesManager.onlineDevices.count)")
        StatCard(title: "Logs", value: "\(devicesManager.totalLogsProcessed)")
      }
    }
    .padding(Constants.standardPadding)
    .frame(maxWidth: .infinity, alignment: .leading)
    .glassEffect(in: .rect(cornerRadius: Constants.cornerRadius, style: .continuous))
  }

  // MARK: - Device Table Section (Wide Layout)

  private var deviceTableSection: some View {
    VStack(alignment: .leading, spacing: Constants.summaryCardSpacing) {
      Text(String(localized: "All Devices"))
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
      deviceSection(
        title: String(localized: "Online Devices"), devices: devicesManager.onlineDevices)
    }

    if !devicesManager.offlineDevices.isEmpty {
      deviceSection(
        title: String(localized: "Offline Devices"), devices: devicesManager.offlineDevices)
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
    ContentUnavailableView(
      String(localized: "No Devices"),
      systemImage: "server.rack",
      description: Text(String(localized: "Connect a device to get started"))
    )
    .frame(maxWidth: .infinity)
  }

  // MARK: - Refresh Button

  private var refreshButton: some View {
    Button {
      Task { await devicesManager.fetchDevices(isManualRefresh: true) }
    } label: {
      Image(systemName: "arrow.clockwise")
        .symbolEffect(.rotate, isActive: devicesManager.isRefreshing)
    }
    .disabled(devicesManager.isRefreshing)
  }
}

// MARK: - Device Card

private struct DeviceCard: View {
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
          if device.displayChipModel != nil || device.memoryGb != nil {
            Text(" · ")
          }
          if let chipModel = device.displayChipModel {
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

      // Logs count
      VStack(spacing: 2) {
        Text("\(device.logsProcessed)")
          .font(.title3)
          .fontWeight(.semibold)
        Text("logs")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
      .frame(minWidth: 50)
    }
    .padding(12)
    .background(.ultraThinMaterial, in: .rect(cornerRadius: 12, style: .continuous))
  }

  private var statusColor: Color {
    device.statusColor == "green" ? .green : .gray
  }
}

#Preview {
  AllDevicesView()
    .environment(DevicesManager(api: .preview))
    .environment(AuthManager(api: .preview))
    .environment(ObserverClient())
    .environment(SharingManager())
    .environment(NavigationState())
}
