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
      ForEach(NavigationItem.allCases.filter { $0 != .localDevice }) { item in
        Tab(item.title, systemImage: item.icon, value: item) {
          NavigationStack {
            detailView(for: item)
            #if !os(macOS)
              .navigationBarTitleDisplayMode(.inline)
            #endif
          }
        }
      }
    }
    #if !os(macOS)
    .tabBarMinimizeBehavior(.onScrollDown)
    .tabViewBottomAccessory {
      LocalDeviceAccessory()
    }
    #endif
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
        #if !os(macOS)
          .navigationBarTitleDisplayMode(.inline)
        #endif
      }
    } detail: {
      detailView(for: selectedItem)
      #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
    }
  }

  // MARK: - Detail View

  @ViewBuilder
  private func detailView(for item: NavigationItem) -> some View {
    switch item {
    case .localDevice:
      LocalDeviceView()
    case .allDevices:
      AllDevicesView()
    case .apiKeys:
      APIKeysView()
    case .logs:
      LogsView()
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
