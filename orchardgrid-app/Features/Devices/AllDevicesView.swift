import SwiftUI

struct AllDevicesView: View {
  @Environment(DevicesManager.self) private var devicesManager
  @Environment(AuthManager.self) private var authManager
  @State private var showAccountSheet = false

  var body: some View {
    ScrollView {
      GlassEffectContainer {
        VStack(alignment: .leading, spacing: Constants.standardSpacing) {
          // Last Updated
          LastUpdatedView(lastUpdatedText: devicesManager.lastUpdatedText)

          // Summary Card
          summaryCard

          // Online Devices
          if !devicesManager.onlineDevices.isEmpty {
            deviceSection(title: "Online Devices", devices: devicesManager.onlineDevices)
          }

          // Offline Devices
          if !devicesManager.offlineDevices.isEmpty {
            deviceSection(title: "Offline Devices", devices: devicesManager.offlineDevices)
          }

          // Empty State
          if devicesManager.devices.isEmpty, !devicesManager.isInitialLoading {
            emptyState
          }

          // Error State
          if let error = devicesManager.lastError {
            errorState(error: error)
          }

          // Placeholder Images for Scrolling Test
          placeholderImagesSection
        }
        .padding(Constants.standardPadding)
      }
    }
    .refreshable {
      if let token = authManager.authToken {
        await devicesManager.fetchDevices(authToken: token, isManualRefresh: true)
      }
    }
    .navigationTitle("All Devices")
    .toolbarRole(.editor)
    .toolbarTitleDisplayMode(.inlineLarge)
    #if os(macOS)
    .withAccountToolbar(showAccountSheet: $showAccountSheet) {
      refreshButton
    }
    #else
    .toolbar {
      if UIDevice.current.userInterfaceIdiom != .phone {
        ToolbarItem { refreshButton }
        ToolbarSpacer(.flexible)
        ToolbarItemGroup {
          Button {
            showAccountSheet = true
          } label: {
            Label("Account", systemImage: "person.circle")
              .labelStyle(.iconOnly)
          }
        }
      } else {
        ToolbarItem { refreshButton }
      }
    }
    .sheet(isPresented: $showAccountSheet) {
      NavigationStack {
        AccountView()
          .navigationBarTitleDisplayMode(.inline)
          .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
              Button(role: .close) {
                showAccountSheet = false
              }
            }
          }
      }
      .presentationDetents([.large])
      .presentationDragIndicator(.visible)
    }
    #endif
    .task {
      if let token = authManager.authToken {
        await devicesManager.fetchDevices(authToken: token)
        await devicesManager.startAutoRefresh(interval: RefreshConfig.interval, authToken: token)
      }
    }
    .onDisappear {
      devicesManager.stopAutoRefresh()
    }
  }

  // MARK: - Summary Card

  private var summaryCard: some View {
    VStack(alignment: .leading, spacing: Constants.summaryCardSpacing) {
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
    .padding(Constants.standardPadding)
    .glassEffect(in: .rect(cornerRadius: Constants.cornerRadius, style: .continuous))
  }

  // MARK: - Device Section

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

  // MARK: - Placeholder Images Section

  private var placeholderImagesSection: some View {
    VStack(alignment: .leading, spacing: Constants.summaryCardSpacing) {
      Text("Gallery")
        .font(.headline)
        .foregroundStyle(.secondary)

      ForEach(placeholderImageURLs, id: \.self) { imageURL in
        AsyncImage(url: imageURL) { phase in
          switch phase {
          case .empty:
            ProgressView()
              .frame(height: 200)
          case let .success(image):
            image
              .resizable()
              .aspectRatio(contentMode: .fill)
              .frame(height: 200)
              .clipped()
          case .failure:
            Image(systemName: "photo")
              .resizable()
              .aspectRatio(contentMode: .fit)
              .frame(height: 200)
              .foregroundStyle(.secondary)
          @unknown default:
            EmptyView()
          }
        }
        .glassEffect(in: .rect(cornerRadius: Constants.cornerRadius, style: .continuous))
      }
    }
  }

  private var placeholderImageURLs: [URL] {
    [
      URL(
        string:
        "https://images.unsplash.com/photo-1756142008570-a3dfb507b037?q=80&w=2370&auto=format&fit=crop&ixlib=rb-4.1.0&ixid=M3wxMjA3fDF8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D"
      )!,
      URL(
        string:
        "https://images.unsplash.com/photo-1759503408354-8cfa8a13115e?q=80&w=2370&auto=format&fit=crop&ixlib=rb-4.1.0&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D"
      )!,
      URL(
        string:
        "https://images.unsplash.com/photo-1758914476570-fb84df0e67ab?q=80&w=2370&auto=format&fit=crop&ixlib=rb-4.1.0&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D"
      )!,
      URL(
        string:
        "https://images.unsplash.com/photo-1756143058430-c71365889d82?q=80&w=2371&auto=format&fit=crop&ixlib=rb-4.1.0&ixid=M3wxMjA3fDF8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D"
      )!,
      URL(
        string:
        "https://images.unsplash.com/photo-1759193591199-78621f7b426d?q=80&w=1287&auto=format&fit=crop&ixlib=rb-4.1.0&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D"
      )!,
      URL(
        string:
        "https://images.unsplash.com/photo-1759327718818-0cfee2207279?q=80&w=2456&auto=format&fit=crop&ixlib=rb-4.1.0&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D"
      )!,
      URL(
        string:
        "https://images.unsplash.com/photo-1759434225861-e834192ccdaf?q=80&w=2370&auto=format&fit=crop&ixlib=rb-4.1.0&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D"
      )!,
      URL(
        string:
        "https://images.unsplash.com/photo-1759329172782-3ef4cec55000?q=80&w=1287&auto=format&fit=crop&ixlib=rb-4.1.0&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D"
      )!,
      URL(
        string:
        "https://images.unsplash.com/photo-1759392658577-4324fb89b991?q=80&w=2370&auto=format&fit=crop&ixlib=rb-4.1.0&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D"
      )!,
    ]
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
    .glassEffect(in: .rect(cornerRadius: 12, style: .continuous))
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
