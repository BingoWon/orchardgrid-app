import SwiftUI

struct MainView: View {
  @Environment(NavigationState.self) private var navigationState
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
    @Bindable var navState = navigationState
    return TabView(selection: $navState.selectedItem) {
      ForEach(NavigationItem.allCases.filter { $0 != .localDevice }) { item in
        Tab(item.title, systemImage: item.icon, value: item) {
          NavigationStack {
            detailView(for: item)
          }
        }
      }
    }
    .tabBarMinimizeBehavior(.onScrollDown)
    .tabViewBottomAccessory {
      LocalDeviceAccessory()
    }
  }

  // MARK: - Split View (iPad & Mac)

  private var splitView: some View {
    @Bindable var navState = navigationState
    return NavigationSplitView(columnVisibility: $columnVisibility) {
      List {
        ForEach(NavigationItem.allCases) { item in
          Button {
            navState.selectedItem = item
          } label: {
            Label(item.title, systemImage: item.icon)
          }
          .buttonStyle(.plain)
          .listRowBackground(
            navState.selectedItem == item
              ? Color.accentColor.opacity(0.2)
              : Color.clear
          )
        }
      }
      .navigationTitle("OrchardGrid")
      .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 300)
    } detail: {
      detailView(for: navigationState.selectedItem)
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
    case .account:
      AccountView()
    }
  }
}

#Preview {
  MainView()
    .environment(AuthManager())
    .environment(NavigationState())
}
