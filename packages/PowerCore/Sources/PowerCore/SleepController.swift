import Foundation
import IOKit.pwr_mgt

/// Owns a single idle-sleep assertion, released unconditionally on teardown so
/// a crash or quit can never leave the Mac permanently awake.
public final class SleepController {

    private var systemAssertion: IOPMAssertionID = 0
    private var displayAssertion: IOPMAssertionID = 0
    private var currentReason = ""

    public private(set) var isHolding = false

    public init() {}
    deinit { release() }

    /// Holds system sleep. The display is left to sleep on its own schedule
    /// unless `keepScreenOn` is set — a dark screen during a render is fine,
    /// and for a locked Mac it is actively wanted.
    public func hold(reason: String, keepScreenOn: Bool) {
        if isHolding {
            updateReason(to: reason)
            syncDisplayAssertion(reason: reason, keepScreenOn: keepScreenOn)
            return
        }

        // PreventUserIdleSystemSleep stops the idle timer only; an explicit
        // Apple-menu Sleep still works, which is what users expect.
        var assertion: IOPMAssertionID = 0
        let rc = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString, &assertion)

        guard rc == kIOReturnSuccess else {
            Log.error("failed to create sleep assertion: \(rc)")
            return
        }

        systemAssertion = assertion
        currentReason = reason
        isHolding = true
        syncDisplayAssertion(reason: reason, keepScreenOn: keepScreenOn)
        Log.info("holding sleep — \(reason)")
    }

    public func release() {
        if systemAssertion != 0 {
            IOPMAssertionRelease(systemAssertion)
            systemAssertion = 0
        }
        releaseDisplayAssertion()
        if isHolding { Log.info("released sleep hold") }
        isHolding = false
        currentReason = ""
    }

    /// Renames the live assertion so `pmset -g assertions` reflects what is
    /// actually happening rather than freezing at the first reason.
    private func updateReason(to reason: String) {
        guard reason != currentReason, systemAssertion != 0 else { return }
        IOPMAssertionSetProperty(systemAssertion,
                                 kIOPMAssertionNameKey as CFString,
                                 reason as CFString)
        currentReason = reason
    }

    private func syncDisplayAssertion(reason: String, keepScreenOn: Bool) {
        guard keepScreenOn else { releaseDisplayAssertion(); return }
        guard displayAssertion == 0 else { return }

        var assertion: IOPMAssertionID = 0
        let rc = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString, &assertion)
        if rc == kIOReturnSuccess { displayAssertion = assertion }
    }

    private func releaseDisplayAssertion() {
        guard displayAssertion != 0 else { return }
        IOPMAssertionRelease(displayAssertion)
        displayAssertion = 0
    }
}
