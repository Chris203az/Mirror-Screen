import AVFoundation

enum PixelFormatPreference: String, CaseIterable, Identifiable {
    /// Decoded 32-bit BGRA frames: always a pixel buffer, so snapshots and stats work.
    case bgra
    /// Whatever the device sends, with no conversion on our side.
    case native

    var id: String { rawValue }

    var label: String {
        switch self {
        case .bgra: return "BGRA (consigliato)"
        case .native: return "Nativo del dispositivo"
        }
    }
}

struct CaptureError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Owns the AVCaptureSession for one device. Video only: the audio half of the muxed stream is never connected.
final class CaptureController: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()

    /// Called on the video queue for every frame.
    var onFrame: (@Sendable (CMSampleBuffer) -> Void)?
    /// Called on the video queue when AVFoundation drops a late frame.
    var onDrop: (@Sendable () -> Void)?
    /// Called on the main queue.
    var onRuntimeError: ((String) -> Void)?
    var onInterrupted: (() -> Void)?

    private let sessionQueue = DispatchQueue(label: "com.chris203az.MirrorScreen.session")
    private let videoQueue = DispatchQueue(label: "com.chris203az.MirrorScreen.video", qos: .userInteractive)
    private let output = AVCaptureVideoDataOutput()
    private var input: AVCaptureDeviceInput?
    private var tokens: [NSObjectProtocol] = []

    override init() {
        super.init()
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: videoQueue)

        let center = NotificationCenter.default
        tokens.append(center.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: .main) { [weak self] note in
            let error = note.userInfo?[AVCaptureSessionErrorKey] as? Error
            self?.onRuntimeError?(error?.localizedDescription ?? "Errore sconosciuto della sessione di cattura")
        })
        tokens.append(center.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: session, queue: .main) { [weak self] _ in
            self?.onInterrupted?()
        })
    }

    /// Starts capturing from `device`, replacing any previous input. `completion` runs on the main queue.
    func start(device: AVCaptureDevice, pixelFormat: PixelFormatPreference, completion: @escaping (Result<Void, Error>) -> Void) {
        sessionQueue.async { [self] in
            let result: Result<Void, Error>
            do {
                try configure(device: device, pixelFormat: pixelFormat)
                session.startRunning()
                result = session.isRunning ? .success(()) : .failure(CaptureError(message: "La sessione di cattura non si è avviata"))
            } catch {
                result = .failure(error)
            }
            DispatchQueue.main.async { completion(result) }
        }
    }

    func stop() {
        sessionQueue.async { [self] in
            if session.isRunning {
                session.stopRunning()
            }
            session.beginConfiguration()
            if let input {
                session.removeInput(input)
                self.input = nil
            }
            session.commitConfiguration()
        }
    }

    private func configure(device: AVCaptureDevice, pixelFormat: PixelFormatPreference) throws {
        if session.isRunning {
            session.stopRunning()
        }
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        if let input {
            session.removeInput(input)
            self.input = nil
        }

        let newInput = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(newInput) else {
            throw CaptureError(message: "Impossibile usare \(device.localizedName) come sorgente")
        }
        session.addInput(newInput)
        input = newInput

        switch pixelFormat {
        case .bgra:
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        case .native:
            // On macOS an empty dictionary means "deliver the device's native format".
            output.videoSettings = [:]
        }
        if !session.outputs.contains(output) {
            guard session.canAddOutput(output) else {
                throw CaptureError(message: "Impossibile ricevere il video da \(device.localizedName)")
            }
            session.addOutput(output)
        }

        selectBestFormat(for: device)
    }

    /// Picks the largest resolution, then the highest frame rate. Set after adding the input so the session keeps it.
    private func selectBestFormat(for device: AVCaptureDevice) {
        let formats = device.formats
        guard formats.count > 1, let best = formats.max(by: Self.isWorse) else { return }
        guard best != device.activeFormat else { return }
        do {
            try device.lockForConfiguration()
            device.activeFormat = best
            device.unlockForConfiguration()
        } catch {
            Log.capture.error("Could not select format: \(error.localizedDescription)")
        }
    }

    private static func isWorse(_ a: AVCaptureDevice.Format, _ b: AVCaptureDevice.Format) -> Bool {
        let da = CMVideoFormatDescriptionGetDimensions(a.formatDescription)
        let db = CMVideoFormatDescriptionGetDimensions(b.formatDescription)
        let areaA = Int(da.width) * Int(da.height)
        let areaB = Int(db.width) * Int(db.height)
        if areaA != areaB {
            return areaA < areaB
        }
        let rateA = a.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0
        let rateB = b.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0
        return rateA < rateB
    }

    // MARK: AVCaptureVideoDataOutputSampleBufferDelegate

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        onFrame?(sampleBuffer)
    }

    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        onDrop?()
    }
}
