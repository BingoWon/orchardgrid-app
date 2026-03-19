import SwiftUI

/// Displays last updated time
struct LastUpdatedView: View {
  let lastUpdatedText: String

  var body: some View {
    Label("Updated \(lastUpdatedText)", systemImage: "clock")
      .font(.caption)
      .foregroundStyle(.secondary)
  }
}

#Preview {
  LastUpdatedView(lastUpdatedText: "2m ago")
    .padding()
}
