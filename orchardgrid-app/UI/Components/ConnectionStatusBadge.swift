import SwiftUI

struct ConnectionStatusBadge: View {
  let isConnected: Bool

  var body: some View {
    HStack(spacing: 4) {
      Circle()
        .fill(isConnected ? .green : .gray)
        .frame(width: 6, height: 6)
      Text(isConnected ? "Live" : "Offline")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }
}
