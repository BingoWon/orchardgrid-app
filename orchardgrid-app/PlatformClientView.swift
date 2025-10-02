/**
 * PlatformClientView.swift
 * OrchardGrid Device Client UI
 *
 * Displays connection status and task processing metrics
 */

import SwiftUI

struct PlatformClientView: View {
  let client: WebSocketClient

  var body: some View {
    VStack(spacing: 20) {
      // Header
      VStack(spacing: 8) {
        Image(systemName: "network")
          .font(.system(size: 48))
          .foregroundStyle(client.isConnected ? .green : .gray)

        Text("OrchardGrid Platform Client")
          .font(.title2)
          .fontWeight(.semibold)

        Text("Phase 1 - Minimum Viable Prototype")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .padding(.top, 20)

      Divider()

      // Connection Status
      VStack(alignment: .leading, spacing: 12) {
        StatusRow(
          icon: "circle.fill",
          iconColor: client.isConnected ? .green : .red,
          label: "Connection",
          value: client.isConnected ? "Connected" : "Disconnected"
        )

        StatusRow(
          icon: "number",
          iconColor: .blue,
          label: "Tasks Processed",
          value: "\(client.tasksProcessed)"
        )

        if let error = client.lastError {
          StatusRow(
            icon: "exclamationmark.triangle.fill",
            iconColor: .orange,
            label: "Last Error",
            value: error
          )
        }
      }
      .padding()
      .background(Color(nsColor: .controlBackgroundColor))
      .cornerRadius(8)

      Spacer()

      // Instructions
      VStack(alignment: .leading, spacing: 8) {
        Text("How to Test")
          .font(.headline)

        Text("1. Make sure this app is running and connected")
          .font(.caption)

        Text("2. Send a request to the platform:")
          .font(.caption)

        Text("""
        curl -X POST https://orchardgrid-platform.bingow.workers.dev/v1/chat/completions \\
          -H "Content-Type: application/json" \\
          -d '{"model": "apple-intelligence", "messages": [{"role": "user", "content": "Hello!"}]}'
        """)
        .font(.system(.caption, design: .monospaced))
        .padding(8)
        .background(Color(nsColor: .textBackgroundColor))
        .cornerRadius(4)

        Text("3. Watch this window for task processing")
          .font(.caption)
      }
      .padding()
      .background(Color(nsColor: .controlBackgroundColor))
      .cornerRadius(8)

      Spacer()
    }
    .padding()
    .frame(width: 600, height: 500)
  }
}

struct StatusRow: View {
  let icon: String
  let iconColor: Color
  let label: String
  let value: String

  var body: some View {
    HStack {
      Image(systemName: icon)
        .foregroundStyle(iconColor)
        .frame(width: 20)

      Text(label)
        .foregroundStyle(.secondary)

      Spacer()

      Text(value)
        .fontWeight(.medium)
    }
  }
}

#Preview {
  PlatformClientView(client: WebSocketClient())
}
