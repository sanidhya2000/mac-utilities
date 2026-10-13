import Foundation
import PowerCore

/// Samples long enough to clear the sustain window, then prints both what is
/// over threshold and what actually qualified. The gap between those two lists
/// is the fastest way to tell a threshold problem from a timing one.
enum Diagnostics {
    static func run() {
        let monitor = ActivityMonitor()
        let sustain = Prefs.shared.sustainSeconds
        let duration = max(14, sustain + 6)

        print("WakeHold diagnostics — sampling for \(duration)s\n")

        let power = BatteryMonitor.current()
        print("Power:      \(power.hasBattery ? "\(power.percentage)%" : "no battery") · "
              + "\(power.onAC ? "AC" : "battery") · lowPower=\(power.lowPowerMode)")
        if let reason = power.blockedReason(Prefs.shared.powerPolicy) {
            print("            holding is BLOCKED — \(reason)")
        }
        print("Thresholds: cpu>=\(Prefs.shared.cpuThreshold)%  "
              + "disk>=\(Prefs.shared.diskThresholdKBps)KB/s  "
              + "net>=\(Prefs.shared.netThresholdKBps)KB/s  "
              + "sustained for \(sustain)s")
        print("Grace:      \(Prefs.shared.graceSeconds)s after work stops\n")

        let deadline = Date().addingTimeInterval(Double(duration))
        while Date() < deadline {
            _ = monitor.tick(Prefs.shared.activityThresholds)
            Thread.sleep(forTimeInterval: 2)
        }
        _ = monitor.tick(Prefs.shared.activityThresholds)

        report("Over threshold", monitor.lastCandidates, empty: "nothing is working")
        report("Qualified (sustained \(sustain)s — these hold sleep)", monitor.lastBusy,
               empty: "nothing sustained long enough")

        let asserting = PowerAssertionReader.appsPreventingSleep()
        print("\nApps holding their own sleep assertion (\(asserting.count)):")
        if asserting.isEmpty { print("  none") }
        for name in asserting { print("  \(name)") }

        let wouldHold = !monitor.lastBusy.isEmpty || !asserting.isEmpty
        print("\nVerdict: \(wouldHold ? "WOULD HOLD sleep" : "would let the Mac sleep")")
    }

    private static func report(_ title: String, _ apps: [BusyApp], empty: String) {
        print("\n\(title) (\(apps.count)):")
        if apps.isEmpty { print("  \(empty)"); return }
        for app in apps.prefix(12) {
            let name = app.display.padding(toLength: 26, withPad: " ", startingAt: 0)
            print("  \(name) \(app.reason)  [busy \(Int(app.busyFor))s]")
        }
    }
}
