import Foundation

/// The tuning an activity sweep needs, supplied by the host app rather than
/// read from a global settings object — that coupling is what kept this code
/// stuck inside one app.
public struct ActivityThresholds {
    public var cpuPercent: Double
    public var diskKBps: Double
    public var netKBps: Double
    /// How long activity must persist before it counts, which is the filter
    /// that stops a brief spike from registering as work.
    public var sustainSeconds: Int
    /// Identifiers to skip entirely.
    public var ignored: Set<String>
    /// Whether another app's own sleep assertion counts as work.
    public var honorAppAssertions: Bool

    public init(cpuPercent: Double = 15,
                diskKBps: Double = 500,
                netKBps: Double = 100,
                sustainSeconds: Int = 10,
                ignored: Set<String> = [],
                honorAppAssertions: Bool = true) {
        self.cpuPercent = cpuPercent
        self.diskKBps = diskKBps
        self.netKBps = netKBps
        self.sustainSeconds = sustainSeconds
        self.ignored = ignored
        self.honorAppAssertions = honorAppAssertions
    }
}

/// Conditions under which holding sleep should stand down.
public struct PowerPolicy {
    /// Stop holding below this battery percentage when on battery.
    public var batteryFloor: Int
    public var respectLowPowerMode: Bool
    /// Hold the display awake as well as the system.
    public var keepScreenOn: Bool

    public init(batteryFloor: Int = 20,
                respectLowPowerMode: Bool = true,
                keepScreenOn: Bool = false) {
        self.batteryFloor = batteryFloor
        self.respectLowPowerMode = respectLowPowerMode
        self.keepScreenOn = keepScreenOn
    }
}
