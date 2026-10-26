import AVFoundation

struct ScreenDevice: Identifiable, Hashable {
    let id: String
    let name: String
    let modelID: String
}

/// Watches for iOS screen capture devices (muxed external devices) appearing and disappearing.
/// Calls `onChange` on the main queue with the current list.
final class DeviceMonitor: NSObject {
    var onChange: (([AVCaptureDevice]) -> Void)?

    private var discovery: AVCaptureDevice.DiscoverySession?
    private var observation: NSKeyValueObservation?
    private var tokens: [NSObjectProtocol] = []

    func start() {
        guard discovery == nil else { return }
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.external],
            mediaType: .muxed,
            position: .unspecified
        )
        discovery = session
        observation = session.observe(\.devices, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.refresh() }
        }
        let center = NotificationCenter.default
        for name in [AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification] {
            tokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.refresh()
            })
        }
        refresh()
    }

    func refresh() {
        var byID: [String: AVCaptureDevice] = [:]
        for device in discovery?.devices ?? [] where Self.isScreenDevice(device) {
            byID[device.uniqueID] = device
        }
        // Older code paths report iOS screens through the legacy API only; merge both to be safe.
        for device in AVCaptureDevice.devices(for: .muxed) where Self.isScreenDevice(device) {
            byID[device.uniqueID] = device
        }
        let devices = byID.values
            .filter { $0.isConnected }
            .sorted { $0.localizedName.localizedCompare($1.localizedName) == .orderedAscending }
        onChange?(devices)
    }

    static func isScreenDevice(_ device: AVCaptureDevice) -> Bool {
        device.hasMediaType(.muxed)
    }
}
