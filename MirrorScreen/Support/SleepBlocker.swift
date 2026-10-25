import IOKit.pwr_mgt

/// Keeps the Mac's display awake while mirroring, useful during presentations.
final class SleepBlocker {
    private var assertionID: IOPMAssertionID = 0
    private var active = false

    func setActive(_ on: Bool) {
        if on, !active {
            let result = IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "Mirroring dell'iPad in corso" as CFString,
                &assertionID
            )
            active = result == kIOReturnSuccess
        } else if !on, active {
            IOPMAssertionRelease(assertionID)
            active = false
        }
    }

    deinit {
        setActive(false)
    }
}
