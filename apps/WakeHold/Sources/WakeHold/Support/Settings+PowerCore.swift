import Foundation
import PowerCore

/// Bridges WakeHold's stored preferences into the value types PowerCore takes.
extension Prefs {
    var activityThresholds: ActivityThresholds {
        ActivityThresholds(
            cpuPercent: cpuThreshold,
            diskKBps: diskThresholdKBps,
            netKBps: netThresholdKBps,
            sustainSeconds: sustainSeconds,
            ignored: ignoredApps,
            honorAppAssertions: honorAppAssertions
        )
    }

    var powerPolicy: PowerPolicy {
        PowerPolicy(
            batteryFloor: batteryThreshold,
            respectLowPowerMode: respectLowPower,
            keepScreenOn: keepScreenOn
        )
    }
}
