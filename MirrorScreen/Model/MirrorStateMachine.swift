import Foundation

/// What the window is showing. Pure value type so it can be unit tested without AVFoundation.
enum MirrorPhase: Equatable {
    case needsPermission
    case permissionDenied
    case waitingForDevice
    case connecting(deviceName: String)
    case streaming(deviceName: String)
    /// The device is still attached but no new frames arrive: iPad locked, screen off or session interrupted.
    case stalled(deviceName: String)
    /// Shown briefly after the device vanishes, then we go back to waiting.
    case disconnected(deviceName: String)
    case failed(message: String)

    var deviceName: String? {
        switch self {
        case .connecting(let name), .streaming(let name), .stalled(let name), .disconnected(let name):
            return name
        default:
            return nil
        }
    }

    /// True when the video layer holds a meaningful image.
    var showsVideo: Bool {
        switch self {
        case .streaming, .stalled: return true
        default: return false
        }
    }
}

enum MirrorEvent: Equatable {
    case permissionGranted
    case permissionDenied
    case connectRequested(deviceName: String)
    case frameReceived
    case framesStalled
    case sessionInterrupted
    case sessionFailed(message: String)
    case deviceDisappeared
    case disconnectNoticeExpired
}

struct MirrorStateMachine {
    private(set) var phase: MirrorPhase

    init(phase: MirrorPhase = .needsPermission) {
        self.phase = phase
    }

    /// Applies an event and returns the new phase. Events that make no sense in the current phase are ignored.
    @discardableResult
    mutating func handle(_ event: MirrorEvent) -> MirrorPhase {
        phase = Self.next(after: phase, on: event)
        return phase
    }

    static func next(after phase: MirrorPhase, on event: MirrorEvent) -> MirrorPhase {
        switch (phase, event) {
        case (.needsPermission, .permissionGranted), (.permissionDenied, .permissionGranted):
            return .waitingForDevice
        case (_, .permissionDenied):
            return .permissionDenied

        case (.needsPermission, _), (.permissionDenied, _):
            return phase

        case (_, .connectRequested(let name)):
            return .connecting(deviceName: name)

        case (.connecting(let name), .frameReceived), (.stalled(let name), .frameReceived):
            return .streaming(deviceName: name)

        case (.streaming(let name), .framesStalled),
             (.streaming(let name), .sessionInterrupted),
             (.connecting(let name), .sessionInterrupted):
            return .stalled(deviceName: name)

        case (.connecting, .sessionFailed(let message)),
             (.streaming, .sessionFailed(let message)),
             (.stalled, .sessionFailed(let message)),
             (.waitingForDevice, .sessionFailed(let message)):
            return .failed(message: message)

        case (.connecting(let name), .deviceDisappeared),
             (.streaming(let name), .deviceDisappeared),
             (.stalled(let name), .deviceDisappeared):
            return .disconnected(deviceName: name)
        case (.failed, .deviceDisappeared):
            return .waitingForDevice

        case (.disconnected, .disconnectNoticeExpired):
            return .waitingForDevice

        default:
            return phase
        }
    }
}
