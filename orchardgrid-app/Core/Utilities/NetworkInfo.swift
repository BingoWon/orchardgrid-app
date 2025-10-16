/**
 * NetworkInfo.swift
 * OrchardGrid Network Information
 *
 * Provides local network IP address detection
 */

import Foundation
#if canImport(Darwin)
  import Darwin
#endif

enum NetworkInfo {
  /// Get the local IP address (WiFi or Ethernet)
  /// Returns the most appropriate IPv4 address for LAN access
  /// Priority: WiFi (en0) > Ethernet (en1) > Other interfaces
  static var localIPAddress: String? {
    var address: String?
    var ifaddr: UnsafeMutablePointer<ifaddrs>?

    // Get list of all network interfaces
    guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
      return nil
    }

    // Iterate through linked list of interfaces
    var ptr = firstAddr
    while true {
      let interface = ptr.pointee

      // Check for IPv4 interface
      let addrFamily = interface.ifa_addr.pointee.sa_family
      if addrFamily == UInt8(AF_INET) {
        // Get interface name
        let name = String(cString: interface.ifa_name)

        // Convert address to string
        var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        getnameinfo(
          interface.ifa_addr,
          socklen_t(interface.ifa_addr.pointee.sa_len),
          &hostname,
          socklen_t(hostname.count),
          nil,
          socklen_t(0),
          NI_NUMERICHOST
        )
        let addressString = String(cString: hostname)

        // Filter out localhost and link-local addresses
        guard !addressString.hasPrefix("127."),
              !addressString.hasPrefix("169.254.")
        else {
          if let next = interface.ifa_next {
            ptr = next
            continue
          } else {
            break
          }
        }

        // Priority: WiFi (en0) > Ethernet (en1) > Other
        if name == "en0" {
          // WiFi - highest priority, return immediately
          address = addressString
          break
        } else if name == "en1", address == nil {
          // Ethernet - second priority
          address = addressString
        } else if address == nil {
          // Other interfaces - lowest priority
          address = addressString
        }
      }

      // Move to next interface
      if let next = interface.ifa_next {
        ptr = next
      } else {
        break
      }
    }

    freeifaddrs(firstAddr)
    return address
  }

  /// Get all available local IP addresses with interface names
  /// Useful for debugging or advanced use cases
  static var allLocalIPAddresses: [(interface: String, address: String)] {
    var addresses: [(String, String)] = []
    var ifaddr: UnsafeMutablePointer<ifaddrs>?

    guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
      return []
    }

    var ptr = firstAddr
    while true {
      let interface = ptr.pointee
      let addrFamily = interface.ifa_addr.pointee.sa_family

      if addrFamily == UInt8(AF_INET) {
        let name = String(cString: interface.ifa_name)
        var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        getnameinfo(
          interface.ifa_addr,
          socklen_t(interface.ifa_addr.pointee.sa_len),
          &hostname,
          socklen_t(hostname.count),
          nil,
          socklen_t(0),
          NI_NUMERICHOST
        )
        let addressString = String(cString: hostname)

        // Include all addresses except localhost
        if !addressString.hasPrefix("127.") {
          addresses.append((name, addressString))
        }
      }

      if let next = interface.ifa_next {
        ptr = next
      } else {
        break
      }
    }

    freeifaddrs(firstAddr)
    return addresses
  }
}
