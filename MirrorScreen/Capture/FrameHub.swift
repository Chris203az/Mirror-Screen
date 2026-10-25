import AVFoundation
import QuartzCore

/// Receives every frame on the video queue: forwards it to the renderer and keeps the bookkeeping
/// (last frame time, counters, dimensions, last image) that the main thread reads for stats and stall detection.
final class FrameHub: @unchecked Sendable {
    struct Snapshot {
        var frameCount: UInt64
        var dropCount: UInt64
        var secondsSinceLastFrame: Double
        var dimensions: CGSize
        var pixelFormat: FourCharCode
    }

    /// Called on the main queue when the frame size changes (first frame, iPad rotated).
    var onDimensionsChanged: ((CGSize) -> Void)?

    private let lock = NSLock()
    private var renderer: AVSampleBufferVideoRenderer?
    private var renderingEnabled = true
    private var lastFrameTime: CFTimeInterval = 0
    private var frameCount: UInt64 = 0
    private var dropCount: UInt64 = 0
    private var dimensions: CGSize = .zero
    private var pixelFormat: FourCharCode = 0
    private var lastPixelBuffer: CVPixelBuffer?

    func setRenderer(_ renderer: AVSampleBufferVideoRenderer?) {
        lock.lock()
        self.renderer = renderer
        lock.unlock()
    }

    func setRenderingEnabled(_ enabled: Bool) {
        lock.lock()
        renderingEnabled = enabled
        lock.unlock()
    }

    func reset() {
        lock.lock()
        lastFrameTime = 0
        frameCount = 0
        dropCount = 0
        dimensions = .zero
        pixelFormat = 0
        lastPixelBuffer = nil
        lock.unlock()
    }

    func receive(_ sampleBuffer: CMSampleBuffer) {
        var size = CGSize.zero
        var format: FourCharCode = 0
        let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        if let pixelBuffer {
            size = CGSize(width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer))
            format = CVPixelBufferGetPixelFormatType(pixelBuffer)
        } else if let description = CMSampleBufferGetFormatDescription(sampleBuffer) {
            let d = CMVideoFormatDescriptionGetDimensions(description)
            size = CGSize(width: Int(d.width), height: Int(d.height))
            format = CMFormatDescriptionGetMediaSubType(description)
        }

        lock.lock()
        let changed = size != .zero && size != dimensions
        lastFrameTime = CACurrentMediaTime()
        frameCount &+= 1
        dimensions = size
        pixelFormat = format
        lastPixelBuffer = pixelBuffer
        let target = renderingEnabled ? renderer : nil
        lock.unlock()

        if let target {
            Self.markDisplayImmediately(sampleBuffer)
            if target.status == .failed {
                target.flush()
            }
            if target.isReadyForMoreMediaData {
                target.enqueue(sampleBuffer)
            }
        }

        if changed {
            DispatchQueue.main.async { [weak self] in
                self?.onDimensionsChanged?(size)
            }
        }
    }

    func noteDrop() {
        lock.lock()
        dropCount &+= 1
        lock.unlock()
    }

    func snapshot() -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        let since = lastFrameTime > 0 ? CACurrentMediaTime() - lastFrameTime : .infinity
        return Snapshot(
            frameCount: frameCount,
            dropCount: dropCount,
            secondsSinceLastFrame: since,
            dimensions: dimensions,
            pixelFormat: pixelFormat
        )
    }

    func latestPixelBuffer() -> CVPixelBuffer? {
        lock.lock()
        defer { lock.unlock() }
        return lastPixelBuffer
    }

    /// Show each frame as soon as it arrives instead of scheduling it against a timebase: lowest latency.
    private static func markDisplayImmediately(_ sampleBuffer: CMSampleBuffer) {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: true),
              CFArrayGetCount(attachments) > 0 else { return }
        let dictionary = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
        CFDictionarySetValue(
            dictionary,
            Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
            Unmanaged.passUnretained(kCFBooleanTrue).toOpaque()
        )
    }
}

extension FourCharCode {
    var fourCCString: String {
        guard self != 0 else { return "—" }
        let bytes = [24, 16, 8, 0].map { UInt8((self >> UInt32($0)) & 0xFF) }
        let text = String(bytes: bytes, encoding: .ascii)?.trimmingCharacters(in: .whitespaces) ?? ""
        return text.isEmpty ? String(self) : text
    }
}
