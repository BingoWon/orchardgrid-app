import SwiftUI

enum NavigationItem: String, CaseIterable, Identifiable {
  case localDevice = "This Mac"
  case allDevices = "All Devices"
  case apiKeys = "API Keys"
  case logs = "Logs"
  case account = "Account"

  var id: String { rawValue }

  var icon: String {
    switch self {
    case .localDevice:
      "desktopcomputer"
    case .allDevices:
      "server.rack"
    case .apiKeys:
      "key.fill"
    case .logs:
      "list.bullet.rectangle"
    case .account:
      "person.circle.fill"
    }
  }
}
