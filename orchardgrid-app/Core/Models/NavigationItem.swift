import SwiftUI

enum NavigationItem: String, CaseIterable, Identifiable {
  case localDevice, allDevices, chats, apiKeys, logs, account

  var id: String { rawValue }

  /// Localized display title for Tab/Sidebar
  var title: String {
    switch self {
    case .localDevice:
      Self.localDeviceTitle
    case .allDevices:
      String(localized: "Devices")
    case .chats:
      String(localized: "Chats")
    case .apiKeys:
      String(localized: "API Keys")
    case .logs:
      String(localized: "Logs")
    case .account:
      String(localized: "Account")
    }
  }

  /// Platform-specific localized title for local device
  static var localDeviceTitle: String {
    #if os(macOS)
      return String(localized: "This Mac")
    #else
      return UIDevice.current.userInterfaceIdiom == .pad
        ? String(localized: "This iPad") : String(localized: "This iPhone")
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
