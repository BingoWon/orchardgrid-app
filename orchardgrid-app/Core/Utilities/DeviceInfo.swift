/**
 * DeviceInfo.swift
 * OrchardGrid Device Information
 *
 * Provides hardware and system information
 */

import Foundation
#if os(macOS)
  import IOKit
#elseif os(iOS)
  import UIKit
#endif

enum DeviceInfo {
  /// Device name (user-configured)
  static var deviceName: String {
    #if os(macOS)
      return Host.current().localizedName ?? "Mac"
    #elseif os(iOS)
      return UIDevice.current.name
    #else
      return "Unknown Device"
    #endif
  }

  /// Chip model (e.g., "Apple M3 Pro", "Intel Core i9")
  static var chipModel: String {
    var size = 0
    sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
    var machine = [CChar](repeating: 0, count: size)
    sysctlbyname("machdep.cpu.brand_string", &machine, &size, nil, 0)
    let brandString = String(cString: machine).trimmingCharacters(in: .whitespaces)

    // Clean up the brand string
    if brandString.contains("Apple") {
      // Extract "Apple M1", "Apple M2 Pro", etc.
      let components = brandString.components(separatedBy: " ")
      if components.count >= 2 {
        // Return "Apple M1" or "Apple M2 Pro"
        return components.prefix(3).joined(separator: " ")
      }
    }

    return brandString
  }

  /// Total physical memory in bytes
  static var totalMemoryBytes: UInt64 {
    ProcessInfo.processInfo.physicalMemory
  }

  /// Total physical memory in GB (formatted)
  static var totalMemoryGB: Double {
    Double(totalMemoryBytes) / 1_073_741_824.0
  }

  /// Formatted memory string (e.g., "16 GB", "36 GB")
  static var formattedMemory: String {
    let gb = totalMemoryGB
    if gb >= 1 {
      return String(format: "%.0f GB", gb)
    } else {
      let mb = Double(totalMemoryBytes) / 1_048_576.0
      return String(format: "%.0f MB", mb)
    }
  }
}
