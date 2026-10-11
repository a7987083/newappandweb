import Foundation

/// Objective-C UI adapter; the UDID acquisition implementation remains in UDIDService.
@objcMembers final class GameStoreDeviceAuthBridge: NSObject {
    class func currentUDID() -> String? {
        return UDIDService.shared.udid
    }

    class func requestAuthentication() {
        UDIDService.shared.requestProfileConfiguration()
    }
}
