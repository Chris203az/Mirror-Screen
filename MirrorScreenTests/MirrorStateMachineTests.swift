import XCTest

final class MirrorStateMachineTests: XCTestCase {
    func testHappyPathReachesStreaming() {
        var machine = MirrorStateMachine()
        machine.handle(.permissionGranted)
        XCTAssertEqual(machine.phase, .waitingForDevice)
        machine.handle(.connectRequested(deviceName: "iPad"))
        XCTAssertEqual(machine.phase, .connecting(deviceName: "iPad"))
        machine.handle(.frameReceived)
        XCTAssertEqual(machine.phase, .streaming(deviceName: "iPad"))
    }

    func testEventsAreIgnoredUntilPermissionIsGranted() {
        var machine = MirrorStateMachine()
        machine.handle(.connectRequested(deviceName: "iPad"))
        XCTAssertEqual(machine.phase, .needsPermission)
        machine.handle(.permissionDenied)
        machine.handle(.frameReceived)
        XCTAssertEqual(machine.phase, .permissionDenied)
    }

    func testLockAndUnlockResumesStreaming() {
        var machine = MirrorStateMachine(phase: .streaming(deviceName: "iPad"))
        machine.handle(.framesStalled)
        XCTAssertEqual(machine.phase, .stalled(deviceName: "iPad"))
        XCTAssertTrue(machine.phase.showsVideo)
        machine.handle(.frameReceived)
        XCTAssertEqual(machine.phase, .streaming(deviceName: "iPad"))
    }

    func testDisconnectShowsNoticeThenWaits() {
        var machine = MirrorStateMachine(phase: .stalled(deviceName: "iPad"))
        machine.handle(.deviceDisappeared)
        XCTAssertEqual(machine.phase, .disconnected(deviceName: "iPad"))
        XCTAssertFalse(machine.phase.showsVideo)
        machine.handle(.disconnectNoticeExpired)
        XCTAssertEqual(machine.phase, .waitingForDevice)
    }

    func testFailureCanBeRetried() {
        var machine = MirrorStateMachine(phase: .connecting(deviceName: "iPad"))
        machine.handle(.sessionFailed(message: "boom"))
        XCTAssertEqual(machine.phase, .failed(message: "boom"))
        machine.handle(.connectRequested(deviceName: "iPad"))
        XCTAssertEqual(machine.phase, .connecting(deviceName: "iPad"))
    }

    func testFailureWithoutDeviceGoesBackToWaiting() {
        var machine = MirrorStateMachine(phase: .failed(message: "boom"))
        machine.handle(.deviceDisappeared)
        XCTAssertEqual(machine.phase, .waitingForDevice)
    }

    func testStallIsIgnoredWhileConnecting() {
        var machine = MirrorStateMachine(phase: .connecting(deviceName: "iPad"))
        machine.handle(.framesStalled)
        XCTAssertEqual(machine.phase, .connecting(deviceName: "iPad"))
    }
}
