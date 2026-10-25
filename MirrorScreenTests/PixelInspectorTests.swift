import CoreVideo
import XCTest

final class PixelInspectorTests: XCTestCase {
    private func makeBuffer(width: Int, height: Int, format: OSType = kCVPixelFormatType_32BGRA) -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, format, nil, &buffer)
        XCTAssertEqual(status, kCVReturnSuccess)
        return buffer!
    }

    func testReadsBGRAPixel() {
        let buffer = makeBuffer(width: 4, height: 3)
        CVPixelBufferLockBaseAddress(buffer, [])
        let base = CVPixelBufferGetBaseAddress(buffer)!
        let pixel = base.advanced(by: 2 * CVPixelBufferGetBytesPerRow(buffer) + 1 * 4).assumingMemoryBound(to: UInt8.self)
        pixel[0] = 0x33 // blue
        pixel[1] = 0x22 // green
        pixel[2] = 0x11 // red
        pixel[3] = 0xFF
        CVPixelBufferUnlockBaseAddress(buffer, [])

        let info = PixelInspector.info(in: buffer, x: 1, y: 2)
        XCTAssertEqual(info.hex, "#112233")
        XCTAssertEqual(info.pointX, 0)
        XCTAssertEqual(info.pointY, 1)
    }

    func testOutOfRangeAndOtherFormatsHaveNoColor() {
        let buffer = makeBuffer(width: 4, height: 3)
        XCTAssertNil(PixelInspector.rgb(in: buffer, x: 4, y: 0))
        XCTAssertNil(PixelInspector.rgb(in: buffer, x: 0, y: -1))

        let yuv = makeBuffer(width: 4, height: 4, format: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)
        XCTAssertNil(PixelInspector.info(in: yuv, x: 0, y: 0).hex)
        XCTAssertNil(PixelInspector.info(in: nil, x: 0, y: 0).hex)
    }
}
