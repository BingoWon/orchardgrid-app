import Foundation
#if os(iOS)
  import UIKit
#endif

class DeviceIdentifier {
  static func get() -> String {
    let key = "com.orchardgrid.deviceID"

    // Return saved ID if exists
    if let saved = UserDefaults.standard.string(forKey: key) {
      return saved
    }

    // Generate new ID
    #if os(iOS)
      let id = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
    #else
      let id = UUID().uuidString
    #endif

    // Save and return
    UserDefaults.standard.set(id, forKey: key)
    return id
  }
}
