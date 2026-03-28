import Foundation

#if os(macOS)
  import IOKit
#elseif os(iOS)
  import UIKit
#endif

enum DeviceInfo {
  static var hardwareID: String {
    let key = "com.orchardgrid.deviceID"
    if let saved = UserDefaults.standard.string(forKey: key) {
      return saved
    }
    #if os(iOS)
      let id = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
    #else
      let id = UUID().uuidString
    #endif
    UserDefaults.standard.set(id, forKey: key)
    return id
  }

  static var deviceName: String {
    #if os(macOS)
      return Host.current().localizedName ?? "Mac"
    #elseif os(iOS)
      return UIDevice.current.name
    #else
      return "Unknown Device"
    #endif
  }

  /// Chip model (e.g., "M3 Pro", "A18 Pro")
  /// The "Apple" prefix is stripped since OrchardGrid is Apple-only.
  static var chipModel: String {
    #if os(macOS)
      var size = 0
      sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)

      guard size > 0 else { return "Unknown" }

      var machine = [CChar](repeating: 0, count: size)
      sysctlbyname("machdep.cpu.brand_string", &machine, &size, nil, 0)

      guard let brandString = String(validatingUTF8: machine) else { return "Unknown" }

      return stripApplePrefix(brandString.trimmingCharacters(in: .whitespaces))
    #elseif os(iOS)
      var size = 0
      sysctlbyname("hw.machine", nil, &size, nil, 0)

      guard size > 0 else { return "Unknown" }

      var machine = [CChar](repeating: 0, count: size)
      sysctlbyname("hw.machine", &machine, &size, nil, 0)

      guard let identifier = String(validatingUTF8: machine) else { return "Unknown" }

      return chipName(for: identifier)
    #else
      return "Unknown"
    #endif
  }

  // MARK: - iOS Chip Mapping

  private static func chipName(for identifier: String) -> String {
    switch identifier {
    // iPhone 17 series (2025)
    case "iPhone18,1": return "A19 Pro"  // iPhone 17 Pro
    case "iPhone18,2": return "A19 Pro"  // iPhone 17 Pro Max
    case "iPhone18,3": return "A19"  // iPhone 17
    case "iPhone18,4": return "A19 Pro"  // iPhone Air
    // iPhone 16 series (2024)
    case "iPhone17,1": return "A18 Pro"  // iPhone 16 Pro
    case "iPhone17,2": return "A18 Pro"  // iPhone 16 Pro Max
    case "iPhone17,3": return "A18"  // iPhone 16
    case "iPhone17,4": return "A18"  // iPhone 16 Plus
    case "iPhone17,5": return "A18"  // iPhone 16e
    // iPhone 15 series (2023)
    case "iPhone16,1": return "A17 Pro"  // iPhone 15 Pro
    case "iPhone16,2": return "A17 Pro"  // iPhone 15 Pro Max
    case "iPhone15,4": return "A16 Bionic"  // iPhone 15
    case "iPhone15,5": return "A16 Bionic"  // iPhone 15 Plus
    default:
      return chipFallback(for: identifier)
    }
  }

  private static func chipFallback(for identifier: String) -> String {
    if identifier.hasPrefix("iPhone") {
      let components = identifier.components(separatedBy: ",")
      if let majorVersion = components.first?.replacingOccurrences(of: "iPhone", with: ""),
        let major = Int(majorVersion)
      {
        if major >= 18 { return "A19" }
        if major >= 17 { return "A18" }
        if major >= 16 { return "A17 Pro" }
        if major >= 15 { return "A16 Bionic" }
      }
    } else if identifier.hasPrefix("iPad") {
      return "M-series"
    }
    return identifier
  }

  // MARK: - Prefix Stripping

  private static func stripApplePrefix(_ raw: String) -> String {
    if raw.hasPrefix("Apple ") {
      let stripped = String(raw.dropFirst(6))
      // For macOS, extract chip name like "M3 Pro", "M2 Max"
      let components = stripped.components(separatedBy: " ")
      return components.prefix(2).joined(separator: " ")
    }
    return raw
  }

  // MARK: - Memory

  static let totalMemoryBytes: UInt64 = ProcessInfo.processInfo.physicalMemory

  static let totalMemoryGB: Double = Double(totalMemoryBytes) / 1_073_741_824.0

  static let formattedMemory: String = {
    let gb = totalMemoryGB
    if gb >= 1 {
      return String(format: "%.0f GB", gb)
    } else {
      let mb = Double(totalMemoryBytes) / 1_048_576.0
      return String(format: "%.0f MB", mb)
    }
  }()
}
