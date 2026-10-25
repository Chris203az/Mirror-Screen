import AVFoundation
import AppKit
import Combine
import CoreImage

struct StreamStats: Equatable {
    var fps: Double = 0
    var resolution: CGSize = .zero
    var pixelFormat: String = "—"
    var dropped: UInt64 = 0
    var secondsSinceLastFrame: Double = 0
}

/// Glue between capture, state machine and UI. All methods are called on the main thread.
final class MirrorViewModel: ObservableObject {
    @Published private(set) var phase: MirrorPhase = .needsPermission
    @Published private(set) var devices: [ScreenDevice] = []
    @Published private(set) var activeDeviceID: String?
    @Published private(set) var stats = StreamStats()
    @Published private(set) var videoSize: CGSize = .zero
    @Published private(set) var toast: String?

    @Published var alwaysOnTop: Bool {
        didSet {
            defaults.set(alwaysOnTop, forKey: Keys.alwaysOnTop)
            windowManager.setFloating(alwaysOnTop)
        }
    }
    @Published var showStats: Bool {
        didSet { defaults.set(showStats, forKey: Keys.showStats) }
    }
    @Published var preventSleep: Bool {
        didSet {
            defaults.set(preventSleep, forKey: Keys.preventSleep)
            updateSleepBlocker()
        }
    }
    @Published var stallDetection: Bool {
        didSet { defaults.set(stallDetection, forKey: Keys.stallDetection) }
    }
    @Published var stallTimeout: Double {
        didSet { defaults.set(stallTimeout, forKey: Keys.stallTimeout) }
    }
    @Published var renderMode: RenderMode {
        didSet {
            defaults.set(renderMode.rawValue, forKey: Keys.renderMode)
            frameHub.setRenderingEnabled(renderMode == .frames)
        }
    }
    @Published var pixelFormat: PixelFormatPreference {
        didSet {
            defaults.set(pixelFormat.rawValue, forKey: Keys.pixelFormat)
            if oldValue != pixelFormat {
                reconnect()
            }
        }
    }

    let windowManager = WindowManager()
    let capture = CaptureController()
    let frameHub = FrameHub()

    private let monitor = DeviceMonitor()
    private let sleepBlocker = SleepBlocker()
    private let defaults = UserDefaults.standard
    private let ciContext = CIContext(options: [.cacheIntermediates: false])
    private var machine = MirrorStateMachine()
    private var deviceObjects: [String: AVCaptureDevice] = [:]
    private var renderer: AVSampleBufferVideoRenderer?
    private var permissionGranted = false
    private var started = false
    private var retryCount = 0
    private var watchdog: Timer?
    private var statsTimer: Timer?
    private var lastStatsFrameCount: UInt64 = 0
    private var lastStatsTime = CACurrentMediaTime()

    private enum Keys {
        static let alwaysOnTop = "alwaysOnTop"
        static let showStats = "showStats"
        static let preventSleep = "preventSleep"
        static let stallDetection = "stallDetection"
        static let stallTimeout = "stallTimeout"
        static let renderMode = "renderMode"
        static let pixelFormat = "pixelFormat"
        static let preferredDevice = "preferredDevice"
    }

    private static let maxRetries = 5

    init() {
        defaults.register(defaults: [
            Keys.alwaysOnTop: false,
            Keys.showStats: false,
            Keys.preventSleep: true,
            Keys.stallDetection: true,
            Keys.stallTimeout: 3.0,
            Keys.renderMode: RenderMode.frames.rawValue,
            Keys.pixelFormat: PixelFormatPreference.bgra.rawValue,
        ])
        alwaysOnTop = defaults.bool(forKey: Keys.alwaysOnTop)
        showStats = defaults.bool(forKey: Keys.showStats)
        preventSleep = defaults.bool(forKey: Keys.preventSleep)
        stallDetection = defaults.bool(forKey: Keys.stallDetection)
        stallTimeout = defaults.double(forKey: Keys.stallTimeout)
        renderMode = RenderMode(rawValue: defaults.string(forKey: Keys.renderMode) ?? "") ?? .frames
        pixelFormat = PixelFormatPreference(rawValue: defaults.string(forKey: Keys.pixelFormat) ?? "") ?? .bgra

        frameHub.setRenderingEnabled(renderMode == .frames)
        let hub = frameHub
        capture.onFrame = { sampleBuffer in hub.receive(sampleBuffer) }
        capture.onDrop = { hub.noteDrop() }
        capture.onRuntimeError = { [weak self] message in self?.fail(message) }
        capture.onInterrupted = { [weak self] in self?.send(.sessionInterrupted) }
        frameHub.onDimensionsChanged = { [weak self] size in self?.videoSizeChanged(size) }
        monitor.onChange = { [weak self] devices in self?.devicesChanged(devices) }
    }

    // MARK: Derived state for the UI

    var hasVideo: Bool { phase.showsVideo && videoSize.width > 0 }

    var windowTitle: String {
        if let name = phase.deviceName, phase.showsVideo {
            return name
        }
        return "MirrorScreen"
    }

    // MARK: Lifecycle

    func start() {
        guard !started else { return }
        started = true
        windowManager.setFloating(alwaysOnTop)
        ScreenCaptureEnabler.enable()
        monitor.start()
        requestPermission()

        watchdog = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.checkFrames()
        }
        statsTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.updateStats()
        }
    }

    func attachRenderer(_ renderer: AVSampleBufferVideoRenderer) {
        self.renderer = renderer
        frameHub.setRenderer(renderer)
    }

    private func requestPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            didGrantPermission()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async { [weak self] in
                    if granted {
                        self?.didGrantPermission()
                    } else {
                        self?.send(.permissionDenied)
                    }
                }
            }
        default:
            send(.permissionDenied)
        }
    }

    private func didGrantPermission() {
        permissionGranted = true
        send(.permissionGranted)
        connectPreferredIfIdle()
    }

    // MARK: Devices

    private func devicesChanged(_ list: [AVCaptureDevice]) {
        var objects: [String: AVCaptureDevice] = [:]
        for device in list {
            objects[device.uniqueID] = device
        }
        deviceObjects = objects
        devices = list.map { ScreenDevice(id: $0.uniqueID, name: $0.localizedName, modelID: $0.modelID) }

        if let active = activeDeviceID, objects[active] == nil {
            teardown(clearImage: true)
            activeDeviceID = nil
            send(.deviceDisappeared)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                guard let self, case .disconnected = self.phase else { return }
                self.send(.disconnectNoticeExpired)
                self.connectPreferredIfIdle()
            }
            return
        }
        if list.isEmpty, case .failed = phase {
            send(.deviceDisappeared)
        }
        connectPreferredIfIdle()
    }

    private func preferredDevice() -> AVCaptureDevice? {
        if let saved = defaults.string(forKey: Keys.preferredDevice), let device = deviceObjects[saved] {
            return device
        }
        return devices.first.flatMap { deviceObjects[$0.id] }
    }

    private func connectPreferredIfIdle() {
        guard permissionGranted, activeDeviceID == nil else { return }
        switch phase {
        case .waitingForDevice, .failed:
            break
        default:
            return
        }
        if let device = preferredDevice() {
            connect(device)
        }
    }

    private func connect(_ device: AVCaptureDevice) {
        activeDeviceID = device.uniqueID
        frameHub.reset()
        videoSize = .zero
        send(.connectRequested(deviceName: device.localizedName))
        let id = device.uniqueID
        capture.start(device: device, pixelFormat: pixelFormat) { [weak self] result in
            guard let self, self.activeDeviceID == id else { return }
            if case .failure(let error) = result {
                self.fail(error.localizedDescription)
            }
        }
    }

    private func fail(_ message: String) {
        Log.capture.error("Capture failed: \(message)")
        teardown(clearImage: false)
        activeDeviceID = nil
        send(.sessionFailed(message: message))
        retryCount += 1
        guard retryCount <= Self.maxRetries else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.connectPreferredIfIdle()
        }
    }

    private func teardown(clearImage: Bool) {
        capture.stop()
        if clearImage {
            renderer?.flush(removingDisplayedImage: true, completionHandler: nil)
        }
    }

    // MARK: User commands

    func selectDevice(_ id: String) {
        defaults.set(id, forKey: Keys.preferredDevice)
        guard id != activeDeviceID, permissionGranted, let device = deviceObjects[id] else { return }
        teardown(clearImage: true)
        activeDeviceID = nil
        retryCount = 0
        connect(device)
    }

    func reconnect() {
        guard permissionGranted else { return }
        let current = activeDeviceID.flatMap { deviceObjects[$0] } ?? preferredDevice()
        teardown(clearImage: true)
        activeDeviceID = nil
        retryCount = 0
        if let current {
            connect(current)
        }
    }

    func copySnapshot() {
        guard let pixelBuffer = frameHub.latestPixelBuffer() else {
            showToast("Nessuna immagine da copiare (prova il formato BGRA)")
            return
        }
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = ciContext.createCGImage(image, from: image.extent) else {
            showToast("Impossibile copiare la schermata")
            return
        }
        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([nsImage])
        showToast("Schermata copiata negli appunti")
    }

    func openCameraPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Frames, stats, state

    private func videoSizeChanged(_ size: CGSize) {
        videoSize = size
        windowManager.updateVideoSize(size)
    }

    private func checkFrames() {
        let since = frameHub.snapshot().secondsSinceLastFrame
        switch phase {
        case .connecting, .stalled:
            if since < 0.5 {
                retryCount = 0
                send(.frameReceived)
            }
        case .streaming:
            if stallDetection, since > stallTimeout {
                send(.framesStalled)
            }
        default:
            break
        }
    }

    private func updateStats() {
        let snapshot = frameHub.snapshot()
        let now = CACurrentMediaTime()
        let elapsed = max(now - lastStatsTime, 0.001)
        let frames = snapshot.frameCount >= lastStatsFrameCount ? snapshot.frameCount - lastStatsFrameCount : snapshot.frameCount
        lastStatsTime = now
        lastStatsFrameCount = snapshot.frameCount
        guard showStats else { return }
        stats = StreamStats(
            fps: Double(frames) / elapsed,
            resolution: snapshot.dimensions,
            pixelFormat: snapshot.pixelFormat.fourCCString,
            dropped: snapshot.dropCount,
            secondsSinceLastFrame: snapshot.secondsSinceLastFrame.isFinite ? snapshot.secondsSinceLastFrame : 0
        )
    }

    private func send(_ event: MirrorEvent) {
        let next = machine.handle(event)
        if next != phase {
            Log.ui.info("Phase: \(String(describing: next))")
            phase = next
        }
        updateSleepBlocker()
    }

    private func updateSleepBlocker() {
        sleepBlocker.setActive(preventSleep && phase.showsVideo)
    }

    private func showToast(_ message: String) {
        toast = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            if self?.toast == message {
                self?.toast = nil
            }
        }
    }
}
