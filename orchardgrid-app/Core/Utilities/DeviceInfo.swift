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

  /// Chip model (e.g., "Apple M3 Pro", "Intel Core i9", "Apple A18 Pro")
  static var chipModel: String {
    #if os(macOS)
      var size = 0
      sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)

      // Check if size is valid
      guard size > 0 else {
        return "Unknown"
      }

      var machine = [CChar](repeating: 0, count: size)
      sysctlbyname("machdep.cpu.brand_string", &machine, &size, nil, 0)

      // Safely create string from C string
      guard let brandString = String(validatingUTF8: machine) else {
        return "Unknown"
      }

      let trimmed = brandString.trimmingCharacters(in: .whitespaces)

      // Clean up the brand string
      if trimmed.contains("Apple") {
        // Extract "Apple M1", "Apple M2 Pro", etc.
        let components = trimmed.components(separatedBy: " ")
        if components.count >= 2 {
          // Return "Apple M1" or "Apple M2 Pro"
          return components.prefix(3).joined(separator: " ")
        }
      }

      return trimmed
    #elseif os(iOS)
      // On iOS, use hw.machine to get device identifier
      var size = 0
      sysctlbyname("hw.machine", nil, &size, nil, 0)

      guard size > 0 else {
        return "Unknown"
      }

      var machine = [CChar](repeating: 0, count: size)
      sysctlbyname("hw.machine", &machine, &size, nil, 0)

      guard let identifier = String(validatingUTF8: machine) else {
        return "Unknown"
      }

      // Map device identifier to chip name
      // Reference: https://www.theiphonewiki.com/wiki/Models
      // iPhone 18,x = iPhone 17 series (A19 / A19 Pro)
      // iPhone 17,x = iPhone 16 series (A18 / A18 Pro)
      // iPhone 16,x = iPhone 15 series (A16 / A17 Pro)

      // Precise mapping based on device identifier
      switch identifier {
      // iPhone 17 series (2025)
      case "iPhone18,1": return "Apple A19 Pro" // iPhone 17 Pro
      case "iPhone18,2": return "Apple A19 Pro" // iPhone 17 Pro Max
      case "iPhone18,3": return "Apple A19" // iPhone 17
      case "iPhone18,4": return "Apple A19 Pro" // iPhone Air
      // iPhone 16 series (2024)
      case "iPhone17,1": return "Apple A18 Pro" // iPhone 16 Pro
      case "iPhone17,2": return "Apple A18 Pro" // iPhone 16 Pro Max
      case "iPhone17,3": return "Apple A18" // iPhone 16
      case "iPhone17,4": return "Apple A18" // iPhone 16 Plus
      case "iPhone17,5": return "Apple A18" // iPhone 16e
      // iPhone 15 series (2023)
      case "iPhone16,1": return "Apple A17 Pro" // iPhone 15 Pro
      case "iPhone16,2": return "Apple A17 Pro" // iPhone 15 Pro Max
      case "iPhone15,4": return "Apple A16 Bionic" // iPhone 15
      case "iPhone15,5": return "Apple A16 Bionic" // iPhone 15 Plus
      default:
        // Fallback: try to extract generation from identifier
        if identifier.hasPrefix("iPhone") {
          let components = identifier.components(separatedBy: ",")
          if let majorVersion = components.first?.replacingOccurrences(of: "iPhone", with: ""),
             let major = Int(majorVersion)
          {
            if major >= 18 {
              return "Apple A19"
            } else if major >= 17 {
              return "Apple A18"
            } else if major >= 16 {
              return "Apple A17 Pro"
            } else if major >= 15 {
              return "Apple A16 Bionic"
            }
          }
        } else if identifier.hasPrefix("iPad") {
          return "Apple M-series or A-series"
        }

        return identifier
      }
    #else
      return "Unknown"
    #endif
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
