import AVFoundation
import AppKit
import SwiftUI

enum RenderMode: String, CaseIterable, Identifiable {
    /// Our own frames into an AVSampleBufferDisplayLayer.
    case frames
    /// AVCaptureVideoPreviewLayer driven by the session, as a fallback to compare against.
    case systemPreview

    var id: String { rawValue }

    var label: String {
        switch self {
        case .frames: return "Frame diretti (consigliato)"
        case .systemPreview: return "Anteprima di sistema"
        }
    }
}

enum GridStyle: String, CaseIterable, Identifiable {
    case none
    case thirds
    case points8

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: return "Nessuna"
        case .thirds: return "Terzi"
        case .points8: return "Griglia da 8 pt"
        }
    }
}

enum BackgroundStyle: String, CaseIterable, Identifiable {
    case black
    case darkGray
    case white

    var id: String { rawValue }

    var label: String {
        switch self {
        case .black: return "Nero"
        case .darkGray: return "Grigio scuro"
        case .white: return "Bianco"
        }
    }

    var nsColor: NSColor {
        switch self {
        case .black: return .black
        case .darkGray: return NSColor(white: 0.15, alpha: 1)
        case .white: return .white
        }
    }

    var color: Color { Color(nsColor: nsColor) }
}

struct VideoView: NSViewRepresentable {
    let model: MirrorViewModel
    let mode: RenderMode
    let videoSize: CGSize
    let gridStyle: GridStyle
    let roundedCorners: Bool
    let background: BackgroundStyle
    let inspectorEnabled: Bool
    let autoHideCursor: Bool

    func makeNSView(context: Context) -> VideoLayerView {
        let view = VideoLayerView()
        let model = self.model
        model.attachVideoView(view)
        view.onHover = { [weak model] pixel in model?.inspect(pixel) }
        view.onPixelClick = { [weak model] pixel in model?.copyColor(at: pixel) }
        view.onZoomChanged = { [weak model] zoom in model?.zoomDidChange(zoom) }
        configure(view)
        return view
    }

    func updateNSView(_ view: VideoLayerView, context: Context) {
        configure(view)
    }

    private func configure(_ view: VideoLayerView) {
        view.apply(mode: mode, session: model.capture.session)
        view.videoSize = videoSize
        view.gridStyle = gridStyle
        view.roundedCorners = roundedCorners
        view.backgroundFill = background.nsColor
        view.inspectorEnabled = inspectorEnabled
        view.autoHideCursor = autoHideCursor
    }
}

/// Hosts the video layer inside a content layer sized to the aspect-fit rectangle.
/// Zoom enlarges that content layer (so the video is rendered sharp at the new size, not scaled as a texture),
/// pan moves it, and the grid and rounded corners follow it.
final class VideoLayerView: NSView {
    static let maxZoom: CGFloat = 8

    let displayLayer = AVSampleBufferDisplayLayer()

    var videoSize: CGSize = .zero {
        didSet { if videoSize != oldValue { needsLayout = true } }
    }
    var gridStyle: GridStyle = .none {
        didSet { if gridStyle != oldValue { needsLayout = true } }
    }
    var roundedCorners = false {
        didSet { if roundedCorners != oldValue { needsLayout = true } }
    }
    var backgroundFill: NSColor = .black {
        didSet { if backgroundFill != oldValue { layer?.backgroundColor = backgroundFill.cgColor } }
    }
    var inspectorEnabled = false {
        didSet {
            guard inspectorEnabled != oldValue else { return }
            if !inspectorEnabled { onHover?(nil) }
            window?.invalidateCursorRects(for: self)
        }
    }
    var autoHideCursor = true

    /// Image pixel under the mouse (top-left origin), or nil when outside the image. Only while the inspector is on.
    var onHover: ((CGPoint?) -> Void)?
    var onPixelClick: ((CGPoint) -> Void)?
    var onZoomChanged: ((CGFloat) -> Void)?

    private(set) var zoom: CGFloat = 1
    private var pan: CGPoint = .zero
    private let contentLayer = CALayer()
    private let gridLayer = CAShapeLayer()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var trackingArea: NSTrackingArea?
    private var cursorTimer: Timer?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = backgroundFill.cgColor
        layer?.masksToBounds = true

        contentLayer.masksToBounds = true
        displayLayer.videoGravity = .resizeAspect
        contentLayer.addSublayer(displayLayer)

        gridLayer.fillColor = nil
        gridLayer.strokeColor = NSColor.systemPink.withAlphaComponent(0.55).cgColor
        gridLayer.lineWidth = 1
        contentLayer.addSublayer(gridLayer)

        layer?.addSublayer(contentLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func apply(mode: RenderMode, session: AVCaptureSession) {
        switch mode {
        case .frames:
            previewLayer?.removeFromSuperlayer()
            previewLayer = nil
            displayLayer.isHidden = false
        case .systemPreview:
            displayLayer.isHidden = true
            if previewLayer == nil {
                let preview = AVCaptureVideoPreviewLayer(session: session)
                preview.videoGravity = .resizeAspect
                preview.frame = contentLayer.bounds
                preview.contentsScale = window?.backingScaleFactor ?? 2
                contentLayer.insertSublayer(preview, below: gridLayer)
                previewLayer = preview
            }
        }
    }

    // MARK: Layout

    override func layout() {
        super.layout()
        clampPan()
        let fit = fittedRect()
        let size = CGSize(width: fit.width * zoom, height: fit.height * zoom)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        contentLayer.bounds = CGRect(origin: .zero, size: size)
        contentLayer.position = CGPoint(x: bounds.midX + pan.x, y: bounds.midY + pan.y)
        // iPad Air 4 corners are about 18 pt on an 820 pt wide screen.
        contentLayer.cornerRadius = roundedCorners ? min(size.width, size.height) * 0.022 : 0
        displayLayer.frame = contentLayer.bounds
        previewLayer?.frame = contentLayer.bounds
        gridLayer.frame = contentLayer.bounds
        gridLayer.path = gridPath(in: size)
        CATransaction.commit()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = window?.backingScaleFactor ?? 2
        displayLayer.contentsScale = scale
        previewLayer?.contentsScale = scale
        gridLayer.contentsScale = scale
    }

    private func fittedRect() -> CGRect {
        guard videoSize.width > 0, videoSize.height > 0 else { return bounds }
        return AVMakeRect(aspectRatio: videoSize, insideRect: bounds)
    }

    private func gridPath(in size: CGSize) -> CGPath? {
        let path = CGMutablePath()
        switch gridStyle {
        case .none:
            return nil
        case .thirds:
            for i in 1...2 {
                let x = size.width * CGFloat(i) / 3
                let y = size.height * CGFloat(i) / 3
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
        case .points8:
            guard videoSize.width > 0 else { return nil }
            // iPads are @2x: 8 points = 16 pixels of the stream.
            let spacing = size.width / videoSize.width * 16
            guard spacing >= 4 else { return nil }
            var x = spacing
            while x < size.width {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                x += spacing
            }
            // Rows counted from the top of the image, like iPad coordinates.
            var y = size.height - spacing
            while y > 0 {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                y -= spacing
            }
        }
        return path
    }

    // MARK: Zoom and pan

    func setZoom(_ requested: CGFloat, around viewPoint: CGPoint? = nil) {
        let newZoom = min(max(requested, 1), Self.maxZoom)
        let anchor = viewPoint.map { CGPoint(x: $0.x - bounds.midX, y: $0.y - bounds.midY) } ?? .zero
        let ratio = newZoom / zoom
        // Keep the image point under the anchor where it is.
        pan = CGPoint(x: anchor.x - (anchor.x - pan.x) * ratio, y: anchor.y - (anchor.y - pan.y) * ratio)
        zoom = newZoom
        clampPan()
        needsLayout = true
        onZoomChanged?(zoom)
    }

    private func clampPan() {
        let fit = fittedRect()
        let maxX = max(0, (fit.width * zoom - bounds.width) / 2)
        let maxY = max(0, (fit.height * zoom - bounds.height) / 2)
        pan = CGPoint(x: min(max(pan.x, -maxX), maxX), y: min(max(pan.y, -maxY), maxY))
    }

    private func panBy(dx: CGFloat, dy: CGFloat) {
        pan = CGPoint(x: pan.x + dx, y: pan.y + dy)
        clampPan()
        needsLayout = true
    }

    override func magnify(with event: NSEvent) {
        setZoom(zoom * (1 + event.magnification), around: convert(event.locationInWindow, from: nil))
    }

    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.option) {
            let factor = 1 + event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 0.01 : 0.1)
            setZoom(zoom * factor, around: convert(event.locationInWindow, from: nil))
        } else if zoom > 1 {
            panBy(dx: event.scrollingDeltaX, dy: -event.scrollingDeltaY)
        } else {
            super.scrollWheel(with: event)
        }
    }

    // MARK: Mouse

    override var mouseDownCanMoveWindow: Bool {
        !inspectorEnabled && zoom == 1
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            setZoom(1)
        } else if inspectorEnabled, let pixel = imagePixel(at: convert(event.locationInWindow, from: nil)) {
            onPixelClick?(pixel)
        } else {
            super.mouseDown(with: event)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        if zoom > 1, !inspectorEnabled {
            panBy(dx: event.deltaX, dy: -event.deltaY)
        } else {
            super.mouseDragged(with: event)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        if inspectorEnabled {
            onHover?(imagePixel(at: convert(event.locationInWindow, from: nil)))
        }
        scheduleCursorHide()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        cursorTimer?.invalidate()
        if inspectorEnabled {
            onHover?(nil)
        }
    }

    override func resetCursorRects() {
        if inspectorEnabled {
            addCursorRect(bounds, cursor: .crosshair)
        }
    }

    private func scheduleCursorHide() {
        cursorTimer?.invalidate()
        guard autoHideCursor, !inspectorEnabled else { return }
        cursorTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { [weak self] _ in
            guard let self, let window = self.window, window.isKeyWindow else { return }
            let point = self.convert(window.mouseLocationOutsideOfEventStream, from: nil)
            if self.bounds.contains(point) {
                NSCursor.setHiddenUntilMouseMoves(true)
            }
        }
    }

    /// Converts a point in this view to a pixel of the iPad image, origin top-left.
    func imagePixel(at point: CGPoint) -> CGPoint? {
        let frame = contentLayer.frame
        guard videoSize.width > 0, frame.width > 0, frame.height > 0, frame.contains(point) else { return nil }
        let u = (point.x - frame.minX) / frame.width
        let v = (frame.maxY - point.y) / frame.height
        let x = min(floor(u * videoSize.width), videoSize.width - 1)
        let y = min(floor(v * videoSize.height), videoSize.height - 1)
        return CGPoint(x: max(x, 0), y: max(y, 0))
    }
}
