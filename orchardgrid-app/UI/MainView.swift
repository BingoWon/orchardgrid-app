import SwiftUI

struct MainView: View {
  @State private var selectedItem: NavigationItem = .allDevices
  @State private var columnVisibility: NavigationSplitViewVisibility = .all

  var body: some View {
    #if os(macOS)
      splitView
    #else
      if UIDevice.current.userInterfaceIdiom == .phone {
        tabView
      } else {
        splitView
      }
    #endif
  }

  // MARK: - Tab View (iPhone)

  private var tabView: some View {
    TabView(selection: $selectedItem) {
      Tab(
        NavigationItem.allDevices.title,
        systemImage: NavigationItem.allDevices.icon,
        value: .allDevices
      ) {
        NavigationStack {
          AllDevicesView()
            .navigationBarTitleDisplayMode(.inline)
        }
      }

      Tab(NavigationItem.apiKeys.title, systemImage: NavigationItem.apiKeys.icon, value: .apiKeys) {
        NavigationStack {
          APIKeysView()
            .navigationBarTitleDisplayMode(.inline)
        }
      }

      Tab(NavigationItem.logs.title, systemImage: NavigationItem.logs.icon, value: .logs) {
        NavigationStack {
          LogsView()
            .navigationBarTitleDisplayMode(.inline)
        }
      }

      Tab(value: .search, role: .search) {
        SearchView()
      }
    }
    .tabBarMinimizeBehavior(.onScrollDown)
    .tabViewBottomAccessory {
      LocalDeviceAccessory()
    }
  }

  // MARK: - Split View (iPad & Mac)

  private var splitView: some View {
    NavigationSplitView(columnVisibility: $columnVisibility) {
      List {
        ForEach(NavigationItem.allCases) { item in
          NavigationLink(value: item) {
            Label(item.title, systemImage: item.icon)
          }
        }
      }
      .navigationTitle("OrchardGrid")
      .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 300)
      .navigationDestination(for: NavigationItem.self) { item in
        detailView(for: item)
          .navigationBarTitleDisplayMode(.inline)
      }
    } detail: {
      detailView(for: selectedItem)
        .navigationBarTitleDisplayMode(.inline)
    }
  }

  // MARK: - Detail View

  @ViewBuilder
  private func detailView(for item: NavigationItem) -> some View {
    switch item {
    case .allDevices:
      AllDevicesView()
    case .apiKeys:
      APIKeysView()
    case .logs:
      LogsView()
    case .search:
      SearchView()
    }
  }
}

#Preview("iPhone") {
  MainView()
    .environment(AuthManager())
}

#Preview("iPad") {
  MainView()
    .environment(AuthManager())
    .previewDevice("iPad Pro (12.9-inch) (6th generation)")
}

#Preview("Mac") {
  MainView()
    .environment(AuthManager())
    .previewDevice("Mac")
}
