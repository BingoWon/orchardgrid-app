import SwiftUI

struct UsageView: View {
  var body: some View {
    PlaceholderView(
      icon: "chart.bar.fill",
      title: "Usage Statistics",
      description: "View your usage statistics here"
    )
    .navigationTitle("Usage")
  }
}

#Preview {
  UsageView()
}
