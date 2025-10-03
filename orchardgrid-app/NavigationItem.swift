import SwiftUI

enum NavigationItem: String, CaseIterable, Identifiable {
  case localDevice = "This Mac"
  case allDevices = "All Devices"
  case apiKeys = "API Keys"
  case usage = "Usage"
  case earnings = "Earnings"
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
    case .usage:
      "chart.bar.fill"
    case .earnings:
      "dollarsign.circle.fill"
    case .account:
      "person.circle.fill"
    }
  }
}
