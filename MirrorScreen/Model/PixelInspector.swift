import CoreVideo
import Foundation

/// What the pixel inspector shows for the pixel under the mouse.
struct PixelInfo: Equatable {
    /// Pixel of the stream, origin top-left.
    let x: Int
    let y: Int
    /// "#RRGGBB", or nil when the frame is not BGRA.
    let hex: String?

    /// iPad coordinates in points (iPads are @2x).
    var pointX: Int { x / 2 }
    var pointY: Int { y / 2 }
}

enum PixelInspector {
    struct RGB: Equatable {
        let red: UInt8
        let green: UInt8
        let blue: UInt8

        var hex: String { String(format: "#%02X%02X%02X", red, green, blue) }
    }

    /// Reads one pixel from a 32BGRA buffer. Returns nil for other formats or out-of-range coordinates.
    static func rgb(in buffer: CVPixelBuffer, x: Int, y: Int) -> RGB? {
        guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA,
              x >= 0, y >= 0,
              x < CVPixelBufferGetWidth(buffer), y < CVPixelBufferGetHeight(buffer) else { return nil }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let offset = y * CVPixelBufferGetBytesPerRow(buffer) + x * 4
        let pixel = base.advanced(by: offset).assumingMemoryBound(to: UInt8.self)
        return RGB(red: pixel[2], green: pixel[1], blue: pixel[0])
    }

    static func info(in buffer: CVPixelBuffer?, x: Int, y: Int) -> PixelInfo {
        let color = buffer.flatMap { rgb(in: $0, x: x, y: y) }
        return PixelInfo(x: x, y: y, hex: color?.hex)
    }
}
