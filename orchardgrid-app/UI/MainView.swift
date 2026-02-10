import SwiftUI

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
    // Single SignInSheet for entire app - prevents multiple sheet conflicts
    .sheet(isPresented: Binding(
      get: { authManager.showSignInSheet },
      set: { authManager.showSignInSheet = $0 }
    )) {
      SignInSheet()
        .environment(authManager)
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
      NavigationStack {
        detailView(for: navigationState.selectedItem)
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
