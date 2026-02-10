import SwiftUI

enum NavigationItem: String, CaseIterable, Identifiable {
  case localDevice = "Local Device"
  case allDevices = "Devices"
  case chats = "Chats"
  case apiKeys = "API Keys"
  case logs = "Logs"
  case account = "Account"

  var id: String { rawValue }

  /// Display title for Tab/Sidebar
  var title: String {
    switch self {
    case .localDevice:
      Self.localDeviceTitle
    default:
      rawValue
    }
  }

  /// Platform-specific title for local device
  static var localDeviceTitle: String {
    #if os(macOS)
      return "This Mac"
    #else
      return UIDevice.current.userInterfaceIdiom == .pad ? "This iPad" : "This iPhone"
    #endif
  }

  /// SF Symbol icon
  var icon: String {
    switch self {
    case .localDevice:
      #if os(macOS)
        return "desktopcomputer"
      #else
        return UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone"
      #endif
    case .allDevices:
      return "server.rack"
    case .chats:
      return "bubble.left.and.bubble.right.fill"
    case .apiKeys:
      return "key.fill"
    case .logs:
      return "list.bullet.rectangle"
    case .account:
      return "person.circle"
    }
  }
}
