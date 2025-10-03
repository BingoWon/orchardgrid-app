import SwiftUI

struct APIKeysView: View {
  var body: some View {
    PlaceholderView(
      icon: "key.fill",
      title: "API Keys",
      description: "Manage your API keys here"
    )
    .navigationTitle("API Keys")
  }
}

#Preview {
  APIKeysView()
}
