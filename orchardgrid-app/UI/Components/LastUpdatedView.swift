import SwiftUI

/// Displays last updated time
struct LastUpdatedView: View {
  let lastUpdatedText: String

  var body: some View {
    HStack {
      Image(systemName: "clock")
        .font(.caption)
        .foregroundStyle(.secondary)
      Text("Updated \(lastUpdatedText)")
        .font(.caption)
        .foregroundStyle(.secondary)
      Spacer()
    }
  }
}

#Preview {
  LastUpdatedView(lastUpdatedText: "2m ago")
    .padding()
}
