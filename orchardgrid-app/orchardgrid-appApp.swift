//
//  giant_bigApp.swift
//  giant_big
//
//  Created by Bin Wang on 10/1/25.
//

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
            CommandGroup(replacing: .newItem) { }
        }
        .windowResizability(.contentSize)
    }
}
