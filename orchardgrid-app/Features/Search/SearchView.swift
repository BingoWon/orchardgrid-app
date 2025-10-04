import SwiftUI

struct SearchView: View {
  @State private var searchText = ""

  var body: some View {
    NavigationStack {
      List {
        if searchText.isEmpty {
          ContentUnavailableView(
            "Search",
            systemImage: "magnifyingglass",
            description: Text("Search for devices, API keys, and logs")
          )
        } else {
          Section("Results") {
            Text("Search results for \"\(searchText)\"")
              .foregroundStyle(.secondary)
          }
        }
      }
      .navigationTitle("Search")
      .searchable(text: $searchText, prompt: "Search OrchardGrid")
    }
  }
}

#Preview {
  SearchView()
}
