/**
 * NavigationState.swift
 * Shared navigation state for cross-view navigation control
 */

import SwiftUI

@Observable
@MainActor
final class NavigationState {
  var selectedItem: NavigationItem = .allDevices

  func navigateTo(_ item: NavigationItem) {
    selectedItem = item
  }
}









