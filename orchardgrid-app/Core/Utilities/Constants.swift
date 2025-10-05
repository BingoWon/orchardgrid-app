import SwiftUI

/// Constant values that the app defines.
enum Constants {
  // MARK: - App-wide constants

  static let cornerRadius: CGFloat = 12.0
  static let standardPadding: CGFloat = 16.0
  static let standardSpacing: CGFloat = 24.0
  static let leadingContentInset: CGFloat = 26.0

  // MARK: - Summary Card constants

  static let summaryCardSpacing: CGFloat = 12.0
  static let summaryCardItemSpacing: CGFloat = 8.0

  // MARK: - Device Card constants

  static let deviceCardSpacing: CGFloat = 16.0
  static let deviceCardItemSpacing: CGFloat = 8.0
  static let deviceCardIconSize: CGFloat = 40.0

  // MARK: - Style

  #if os(macOS)
    static let editingBackgroundStyle = WindowBackgroundShapeStyle.windowBackground
  #else
    static let editingBackgroundStyle = Material.ultraThickMaterial
  #endif
}
