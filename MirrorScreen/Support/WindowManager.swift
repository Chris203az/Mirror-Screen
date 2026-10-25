import AppKit
import SwiftUI

/// Keeps the window's content in the video's aspect ratio and implements the size commands.
final class WindowManager {
    private(set) weak var window: NSWindow?
    private var videoSize: CGSize = .zero
    private var floating = false

    func attach(_ window: NSWindow) {
        guard self.window !== window else { return }
        self.window = window
        window.backgroundColor = .black
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.level = floating ? .floating : .normal
        if videoSize.width > 0 {
            window.contentAspectRatio = videoSize
        }
    }

    func setFloating(_ on: Bool) {
        floating = on
        window?.level = on ? .floating : .normal
    }

    /// Called when the first frame arrives or the iPad rotates.
    func updateVideoSize(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let previous = videoSize
        videoSize = size
        guard let window else { return }
        window.contentAspectRatio = size
        guard !window.styleMask.contains(.fullScreen) else { return }

        let current = window.contentLayoutRect.size
        let newAspect = size.width / size.height
        let currentAspect = current.width / max(current.height, 1)
        let rotated = previous.width > 0 && abs(previous.width / previous.height - newAspect) > 0.01
        if rotated || abs(currentAspect - newAspect) > 0.01 {
            // Keep roughly the same area so a rotation does not make the window jump in size.
            let area = current.width * current.height
            let width = (area * newAspect).squareRoot()
            setContentSize(CGSize(width: width, height: width / newAspect))
        }
    }

    /// One iPad pixel per screen pixel.
    func actualSize() {
        guard let window, videoSize.width > 0 else { return }
        exitFullScreenIfNeeded()
        let scale = window.backingScaleFactor
        setContentSize(CGSize(width: videoSize.width / scale, height: videoSize.height / scale))
    }

    /// As large as the screen allows, keeping the aspect ratio.
    func fitToScreen() {
        guard window != nil, videoSize.width > 0 else { return }
        exitFullScreenIfNeeded()
        setContentSize(CGSize(width: videoSize.width * 100, height: videoSize.height * 100))
    }

    func toggleFullScreen() {
        window?.toggleFullScreen(nil)
    }

    private func exitFullScreenIfNeeded() {
        if let window, window.styleMask.contains(.fullScreen) {
            window.toggleFullScreen(nil)
        }
    }

    /// Sets the content size, scaled down to fit the visible screen, keeping the window centred where it was.
    private func setContentSize(_ requested: CGSize) {
        guard let window, let screen = window.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let chrome = window.frame.height - window.contentLayoutRect.height
        let maxContent = CGSize(width: visible.width, height: visible.height - chrome)

        var size = requested
        let shrink = min(1, maxContent.width / size.width, maxContent.height / size.height)
        size = CGSize(width: (size.width * shrink).rounded(), height: (size.height * shrink).rounded())

        let center = CGPoint(x: window.frame.midX, y: window.frame.midY)
        var frame = window.frameRect(forContentRect: CGRect(origin: .zero, size: size))
        frame.origin = CGPoint(x: center.x - frame.width / 2, y: center.y - frame.height / 2)
        frame.origin.x = min(max(frame.origin.x, visible.minX), visible.maxX - frame.width)
        frame.origin.y = min(max(frame.origin.y, visible.minY), visible.maxY - frame.height)
        window.setFrame(frame, display: true, animate: true)
    }
}

/// Hands the hosting NSWindow to `onWindow` once the view is in a window.
struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> AccessorView {
        let view = AccessorView()
        view.onWindow = onWindow
        return view
    }

    func updateNSView(_ view: AccessorView, context: Context) {
        view.onWindow = onWindow
    }

    final class AccessorView: NSView {
        var onWindow: ((NSWindow) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window {
                onWindow?(window)
            }
        }
    }
}
