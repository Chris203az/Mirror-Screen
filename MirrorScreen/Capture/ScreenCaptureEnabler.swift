import CoreMediaIO
import os

enum ScreenCaptureEnabler {
    /// Lets iOS/iPadOS devices connected over USB show up as AVCaptureDevices, the same switch QuickTime flips.
    /// Must run before the first device discovery; devices appear a few seconds later.
    @discardableResult
    static func enable() -> Bool {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyAllowScreenCaptureDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        var allow: UInt32 = 1
        let status = CMIOObjectSetPropertyData(
            CMIOObjectID(kCMIOObjectSystemObject),
            &address,
            0,
            nil,
            UInt32(MemoryLayout<UInt32>.size),
            &allow
        )
        if status != 0 {
            Log.capture.error("Enabling screen capture devices failed: \(status)")
        }
        return status == 0
    }
}

enum Log {
    static let capture = Logger(subsystem: "com.chris203az.MirrorScreen", category: "capture")
    static let ui = Logger(subsystem: "com.chris203az.MirrorScreen", category: "ui")
}
