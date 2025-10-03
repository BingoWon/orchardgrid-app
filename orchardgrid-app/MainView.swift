import SwiftUI

struct MainView: View {
  @Environment(WebSocketClient.self) private var wsClient
  @State private var selectedItem: NavigationItem? = .localDevice
  @State private var columnVisibility: NavigationSplitViewVisibility = .all

  var body: some View {
    NavigationSplitView(columnVisibility: $columnVisibility) {
      // Sidebar
      List(NavigationItem.allCases, selection: $selectedItem) { item in
        NavigationLink(value: item) {
          Label(item.rawValue, systemImage: item.icon)
        }
      }
      .navigationTitle("OrchardGrid")
      .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 300)
    } detail: {
      // Detail
      if let selectedItem {
        detailView(for: selectedItem)
      } else {
        Text("Select an item")
          .foregroundStyle(.secondary)
      }
    }
    .task {
      // Auto-connect if enabled and not connected
      if wsClient.isEnabled, !wsClient.isConnected, wsClient.userID != nil {
        Logger.log(.app, "Auto-connecting on app launch...")
        wsClient.connect()
      }
    }
  }

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
}
