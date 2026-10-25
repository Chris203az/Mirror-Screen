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

struct VideoView: NSViewRepresentable {
    let model: MirrorViewModel
    let mode: RenderMode

    func makeNSView(context: Context) -> VideoLayerView {
        let view = VideoLayerView()
        model.attachRenderer(view.displayLayer.sampleBufferRenderer)
        view.apply(mode: mode, session: model.capture.session)
        return view
    }

    func updateNSView(_ view: VideoLayerView, context: Context) {
        view.apply(mode: mode, session: model.capture.session)
    }
}

final class VideoLayerView: NSView {
    let displayLayer = AVSampleBufferDisplayLayer()
    private var previewLayer: AVCaptureVideoPreviewLayer?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        displayLayer.videoGravity = .resizeAspect
        displayLayer.backgroundColor = NSColor.black.cgColor
        layer?.addSublayer(displayLayer)
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
                preview.frame = bounds
                preview.contentsScale = window?.backingScaleFactor ?? 2
                layer?.addSublayer(preview)
                previewLayer = preview
            }
        }
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        displayLayer.frame = bounds
        previewLayer?.frame = bounds
        CATransaction.commit()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = window?.backingScaleFactor ?? 2
        displayLayer.contentsScale = scale
        previewLayer?.contentsScale = scale
    }
}
