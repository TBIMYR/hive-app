import IOKit.pwr_mgt

/// Holds an IOKit power assertion against idle sleep (the display may still turn off), like
/// `caffeinate -i`. macOS drops it automatically when the app ends.
@MainActor
final class SleepGuard {
    private var id: IOPMAssertionID = 0
    private var reason: String?

    var isHolding: Bool { reason != nil }

    /// nil releases the assertion; a new reason replaces the old one.
    func hold(_ newReason: String?) {
        guard newReason != reason else { return }
        if reason != nil {
            IOPMAssertionRelease(id)
            reason = nil
        }
        guard let newReason else { return }
        if IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                                       IOPMAssertionLevel(kIOPMAssertionLevelOn), newReason as CFString, &id) == kIOReturnSuccess {
            reason = newReason
        }
    }
}
