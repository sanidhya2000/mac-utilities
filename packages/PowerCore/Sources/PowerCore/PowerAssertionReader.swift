import Foundation
import IOKit.pwr_mgt
import AppKit

/// Reads the "don't sleep" assertions other apps hold — the signal a browser
/// raises during a download, or a video editor during an export. Treating these
/// as work is what lets WakeHold cooperate with apps that already know they are
/// busy, instead of second-guessing them from CPU alone.
public enum PowerAssertionReader {

    /// Assertion types that genuinely block system sleep. Display-only
    /// assertions are excluded: a bright screen is not work.
    private static let blockingTypes: Set<String> = [
        kIOPMAssertionTypePreventUserIdleSystemSleep as String,
        kIOPMAssertionTypeNoIdleSleep as String,
        kIOPMAssertionTypePreventSystemSleep as String,
    ]

    /// Identifiers (bundle id, else process name) of apps currently holding a
    /// sleep-blocking assertion, excluding WakeHold itself.
    public static func appsPreventingSleep() -> [String] {
        var unmanaged: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&unmanaged) == kIOReturnSuccess,
              let byProcess = unmanaged?.takeRetainedValue() as? [NSNumber: [[String: Any]]]
        else { return [] }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        var found: Set<String> = []

        for (pidNumber, assertions) in byProcess {
            let pid = pid_t(truncating: pidNumber)
            guard pid != ownPID else { continue }

            let blocks = assertions.contains { assertion in
                guard let type = assertion[kIOPMAssertionTypeKey as String] as? String else { return false }
                guard blockingTypes.contains(type) else { return false }
                // Level 0 means the assertion exists but is currently off.
                let level = assertion[kIOPMAssertionLevelKey as String] as? Int ?? kIOPMAssertionLevelOn
                return level != 0
            }
            guard blocks else { continue }

            if let app = NSRunningApplication(processIdentifier: pid) {
                found.insert(app.bundleIdentifier ?? app.localizedName ?? "pid \(pid)")
            } else {
                found.insert("pid \(pid)")
            }
        }
        return found.sorted()
    }
}
