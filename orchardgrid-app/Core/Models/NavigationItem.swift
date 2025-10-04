import SwiftUI

enum NavigationItem: String, CaseIterable, Identifiable {
  case localDevice = "Local Device"
  case allDevices = "All Devices"
  case apiKeys = "API Keys"
  case logs = "Logs"
  case account = "Account"

  var id: String { rawValue }

  /// Sidebar display title (platform-specific)
  var sidebarTitle: String {
    switch self {
    case .localDevice:
      #if os(macOS)
        return "This Mac"
      #elseif os(iOS)
        return "This iPhone"
      #else
        return "This iPad"
      #endif
    default:
      return rawValue
    }
  }

  /// Navigation bar title (device name)
  var navigationTitle: String {
    switch self {
    case .localDevice:
      DeviceInfo.deviceName
    default:
      rawValue
    }
  }

  /// SF Symbol icon (platform-specific)
  var icon: String {
    switch self {
    case .localDevice:
      #if os(macOS)
        return "laptopcomputer"
      #elseif os(iOS)
        return "iphone.gen3"
      #else
        return "ipad.gen2"
      #endif
    case .allDevices:
      return "server.rack"
    case .apiKeys:
      return "key.fill"
    case .logs:
      return "list.bullet.rectangle"
    case .account:
      return "person.circle.fill"
    }
  }
}
