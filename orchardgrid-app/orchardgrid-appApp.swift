import SwiftUI

@main
struct OrchardGridApp: App {
  @State private var client = WebSocketClient()

  var body: some Scene {
    WindowGroup {
      PlatformClientView(client: client)
        .task {
          await client.connect()
        }
        .onDisappear {
          client.disconnect()
        }
    }
    .commands {
      CommandGroup(replacing: .newItem) {}
    }
    .windowResizability(.contentSize)
  }
}
