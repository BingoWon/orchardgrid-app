import Foundation
#if os(iOS)
  import UIKit
#endif

enum DeviceID {
  static var current: String {
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
}
