import SwiftUI

#if os(iOS)
  import ClerkKitUI
#endif

struct MainView: View {
  @Environment(NavigationState.self) private var navigationState
  @Environment(AuthManager.self) private var authManager
  @State private var columnVisibility: NavigationSplitViewVisibility = .all
  @State private var showLocalDeviceSheet = false

  var body: some View {
    Group {
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
    .sheet(isPresented: Bindable(authManager).showAuthSheet) {
      #if os(iOS)
        AuthView()
      #else
        SignInView()
      #endif
    }
    .onChange(of: authManager.isAuthenticated) { _, isAuth in
      if isAuth { authManager.showAuthSheet = false }
    }
  }

  // MARK: - Tab View (iPhone only)

  #if !os(macOS)
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
        LocalDeviceAccessory(showSheet: $showLocalDeviceSheet)
      }
      .sheet(isPresented: $showLocalDeviceSheet) {
        NavigationStack {
          LocalDeviceView()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
              ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                  showLocalDeviceSheet = false
                }
              }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
      }
    }
  #endif

  // MARK: - Split View (iPad & Mac)

  private var splitView: some View {
    @Bindable var navState = navigationState
    let selection = Binding<NavigationItem?>(
      get: { navState.selectedItem },
      set: { if let item = $0 { navState.selectedItem = item } }
    )
    return NavigationSplitView(columnVisibility: $columnVisibility) {
      List(NavigationItem.allCases, id: \.self, selection: selection) { item in
        Label(item.title, systemImage: item.icon)
      }
      .navigationTitle("OrchardGrid")
      .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 300)
    } detail: {
      NavigationStack {
        detailView(for: navigationState.selectedItem)
          .backgroundExtensionEffect()
          #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
          #endif
      }
      .id(navigationState.selectedItem)
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
    case .chats:
      ChatsView()
    case .apiKeys:
      APIKeysView()
    case .logs:
      LogsView()
    case .settings:
      SettingsView()
    }
  }
}

#Preview {
  MainView()
    .environment(AuthManager(api: .preview))
    .environment(NavigationState())
}
