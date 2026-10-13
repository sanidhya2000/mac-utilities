import Foundation
import AppKit
import PowerCore
import IOKit.pwr_mgt

/// Reports whether AFK can do its job on this machine, without arming a
/// session — in particular whether the system lock call resolved.
enum Diagnostics {
    @MainActor
    static func run() {
        setbuf(stdout, nil)
        print("AFK diagnostics\n")

        print("screen lock: \(ScreenLock.usesSystemLock ? "system call available" : "FALLBACK to ⌃⌘Q")")

        let power = BatteryMonitor.current()
        print("power:       \(power.hasBattery ? "\(power.percentage)%" : "no battery") · "
              + "\(power.onAC ? "AC" : "battery") · lowPower=\(power.lowPowerMode)")

        let policy = Prefs.shared.powerPolicy
        if let reason = power.blockedReason(policy) {
            print("             arming would be REFUSED — \(reason)")
        } else {
            print("             arming allowed")
        }

        print("\nsettings:")
        print("  release mode:  \(Prefs.shared.releaseMode.label)")
        print("  timer:         \(Prefs.shared.timerMinutes) min")
        print("  safety cap:    \(Prefs.shared.maxHours) h")
        print("  battery floor: \(Prefs.shared.batteryFloor)%")
        print("  lock on arm:   \(Prefs.shared.lockOnArm)")
        print("  lid closed:    \(Prefs.shared.allowLidClosed)")

        print("\nclamshell sleep currently disabled: \(ClamshellController.isDisabled)")

        let asserting = PowerAssertionReader.appsPreventingSleep()
        _ = asserting
        print("\napps already holding sleep (\(asserting.count)):")
        if asserting.isEmpty { print("  none") }
        for name in asserting.prefix(8) { print("  \(name)") }
    }
}


/// Arms a real session with the lock suppressed, holds briefly, then ends it —
/// proof that the assertion is taken and released on this machine.
enum DryRun {
    @MainActor
    static func run(seconds: Int) {
        setbuf(stdout, nil)
        print("AFK dry run — arming for \(seconds)s WITHOUT locking the screen\n")

        let session = AwaySession()
        session.suppressLockForDryRun = true
        session.arm()

        guard session.state.isActive else {
            print("FAILED to arm — see the refusal above")
            exit(1)
        }
        print("armed: \(session.state)")

        let deadline = Date().addingTimeInterval(Double(seconds))
        var reported = false
        while Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(1))
            if !reported, Date().timeIntervalSince(deadline) > Double(-seconds) + 6 {
                let held = ourAssertionNames()
                print("assertion visible to system: \(held.isEmpty ? "NONE ❌" : held.joined(separator: ", "))")
                reported = true
            }
        }

        session.cancel()
        print("\nafter cancel, our assertions: \(ourAssertionNames().isEmpty ? "none ✓ (released cleanly)" : "STILL HELD ❌")")

        if let report = session.lastReport {
            print("report: ended because \(report.endReason.rawValue), "
                  + "lasted \(Int(report.duration))s, saw \(report.appsSeen.count) apps working")
        }
    }

    /// Names of assertions owned by this process, read back from the system.
    private static func ourAssertionNames() -> [String] {
        var unmanaged: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&unmanaged) == kIOReturnSuccess,
              let byProcess = unmanaged?.takeRetainedValue() as? [NSNumber: [[String: Any]]]
        else { return [] }

        let pid = NSNumber(value: ProcessInfo.processInfo.processIdentifier)
        return (byProcess[pid] ?? []).compactMap { $0[kIOPMAssertionNameKey as String] as? String }
    }
}
