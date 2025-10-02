/**
 * DashboardView.swift
 * OrchardGrid User Dashboard
 *
 * Unified interface for providers and consumers
 */

import SwiftUI

struct DashboardView: View {
  @Environment(AuthManager.self) private var authManager
  @Environment(WebSocketClient.self) private var wsClient

  var body: some View {
    TabView {
      // Tab 1: Device Status
      DeviceStatusView()
        .tabItem {
          Label("Device", systemImage: "cpu")
        }

      // Tab 2: API Keys
      APIKeysView()
        .tabItem {
          Label("API Keys", systemImage: "key")
        }

      // Tab 3: Usage Stats
      UsageStatsView()
        .tabItem {
          Label("Usage", systemImage: "chart.bar")
        }

      // Tab 4: Earnings
      EarningsView()
        .tabItem {
          Label("Earnings", systemImage: "dollarsign.circle")
        }

      // Tab 5: Account
      AccountView()
        .tabItem {
          Label("Account", systemImage: "person")
        }
    }
    .frame(minWidth: 800, minHeight: 600)
  }
}

// MARK: - Device Status View

struct DeviceStatusView: View {
  @Environment(WebSocketClient.self) private var wsClient

  var body: some View {
    VStack(spacing: 20) {
      // Header
      HStack {
        VStack(alignment: .leading) {
          Text("Device Status")
            .font(.largeTitle.bold())
          Text("Your computing provider status")
            .foregroundStyle(.secondary)
        }
        Spacer()
      }
      .padding()

      // Status card
      GroupBox {
        VStack(spacing: 16) {
          HStack {
            Image(systemName: wsClient.isConnected ? "checkmark.circle.fill" : "xmark.circle.fill")
              .font(.title)
              .foregroundStyle(wsClient.isConnected ? .green : .red)

            VStack(alignment: .leading) {
              Text(wsClient.isConnected ? "Connected" : "Disconnected")
                .font(.headline)
              Text(wsClient.isConnected ? "Ready to process tasks" : "Not connected to platform")
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()
          }

          Divider()

          // Stats
          HStack(spacing: 40) {
            StatView(title: "Tasks Processed", value: "\(wsClient.tasksProcessed)")
            StatView(title: "Success Rate", value: "100%")
            StatView(title: "Uptime", value: "24h")
          }
        }
        .padding()
      }
      .padding()

      Spacer()
    }
  }
}

struct StatView: View {
  let title: String
  let value: String

  var body: some View {
    VStack {
      Text(value)
        .font(.title.bold())
      Text(title)
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }
}

// MARK: - API Keys View

struct APIKeysView: View {
  var body: some View {
    VStack {
      Text("API Keys")
        .font(.largeTitle.bold())
      Text("Manage your API keys for consuming computing resources")
        .foregroundStyle(.secondary)
      Spacer()
      Text("Coming soon...")
        .foregroundStyle(.secondary)
      Spacer()
    }
    .padding()
  }
}

// MARK: - Usage Stats View

struct UsageStatsView: View {
  var body: some View {
    VStack {
      Text("Usage Statistics")
        .font(.largeTitle.bold())
      Text("Your computing resource consumption")
        .foregroundStyle(.secondary)
      Spacer()
      Text("Coming soon...")
        .foregroundStyle(.secondary)
      Spacer()
    }
    .padding()
  }
}

// MARK: - Earnings View

struct EarningsView: View {
  var body: some View {
    VStack {
      Text("Earnings")
        .font(.largeTitle.bold())
      Text("Your revenue from providing computing resources")
        .foregroundStyle(.secondary)
      Spacer()
      Text("Coming soon...")
        .foregroundStyle(.secondary)
      Spacer()
    }
    .padding()
  }
}

// MARK: - Account View

struct AccountView: View {
  @Environment(AuthManager.self) private var authManager

  var body: some View {
    VStack(spacing: 20) {
      // Header
      HStack {
        VStack(alignment: .leading) {
          Text("Account")
            .font(.largeTitle.bold())
          Text("Manage your OrchardGrid account")
            .foregroundStyle(.secondary)
        }
        Spacer()
      }
      .padding()

      // User info
      if let user = authManager.currentUser {
        GroupBox {
          VStack(alignment: .leading, spacing: 12) {
            HStack {
              Image(systemName: "person.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.blue.gradient)

              VStack(alignment: .leading) {
                Text(user.name ?? "User")
                  .font(.title2.bold())
                Text(user.email)
                  .font(.body)
                  .foregroundStyle(.secondary)
              }

              Spacer()
            }
          }
          .padding()
        }
        .padding()
      }

      Spacer()

      // Logout button
      Button(role: .destructive) {
        authManager.logout()
      } label: {
        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.large)
      .padding()
    }
  }
}

#Preview {
  DashboardView()
    .environment(AuthManager())
    .environment(WebSocketClient(
      serverURL: "wss://orchardgrid-api.bingow.workers.dev/device/connect",
      deviceID: "preview-device",
      userID: "preview-user"
    ))
}
