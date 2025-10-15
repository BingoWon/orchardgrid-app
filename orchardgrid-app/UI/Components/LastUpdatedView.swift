import SwiftUI

/// Displays last updated time and auto-refresh status
struct LastUpdatedView: View {
  let lastUpdatedText: String
  let isAutoRefreshEnabled: Bool
  
  var body: some View {
    HStack {
      Image(systemName: "clock")
        .font(.caption)
        .foregroundStyle(.secondary)
      Text("Updated \(lastUpdatedText)")
        .font(.caption)
        .foregroundStyle(.secondary)
      Spacer()
      if isAutoRefreshEnabled {
        HStack(spacing: 4) {
          Circle()
            .fill(.green)
            .frame(width: 6, height: 6)
          Text("Auto-refresh")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
    }
  }
}

#Preview {
  VStack(spacing: 16) {
    LastUpdatedView(lastUpdatedText: "2m ago", isAutoRefreshEnabled: false)
    LastUpdatedView(lastUpdatedText: "Just now", isAutoRefreshEnabled: true)
  }
  .padding()
}

