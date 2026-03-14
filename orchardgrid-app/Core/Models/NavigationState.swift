import SwiftUI

@Observable
@MainActor
final class NavigationState {
  var selectedItem: NavigationItem = .allDevices
}
