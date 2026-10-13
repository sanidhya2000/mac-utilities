import Foundation
import IOKit.ps

/// Battery charge, power source and Low Power Mode.
public struct PowerState {
    public let onAC: Bool
    public let percentage: Int
    public let lowPowerMode: Bool
    public let hasBattery: Bool

    public init(onAC: Bool, percentage: Int, lowPowerMode: Bool, hasBattery: Bool) {
        self.onAC = onAC
        self.percentage = percentage
        self.lowPowerMode = lowPowerMode
        self.hasBattery = hasBattery
    }

    /// Desktops have no battery, so the floor never applies to them.
    public func batteryTooLow(floor: Int) -> Bool {
        guard hasBattery, !onAC else { return false }
        return percentage < floor
    }

    /// Why holding sleep is not allowed right now, or nil when it is.
    public func blockedReason(_ policy: PowerPolicy) -> String? {
        if policy.respectLowPowerMode && lowPowerMode { return "Low Power Mode is on" }
        if batteryTooLow(floor: policy.batteryFloor) { return "battery below \(policy.batteryFloor)%" }
        return nil
    }
}

public enum BatteryMonitor {

    public static func current() -> PowerState {
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else {
            return PowerState(onAC: true, percentage: 100, lowPowerMode: lowPower, hasBattery: false)
        }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(blob, source)?
                .takeUnretainedValue() as? [String: Any] else { continue }

            let state = description[kIOPSPowerSourceStateKey] as? String
            let current = description[kIOPSCurrentCapacityKey] as? Int ?? 100
            let maximum = description[kIOPSMaxCapacityKey] as? Int ?? 100
            let percentage = maximum > 0 ? Int(Double(current) / Double(maximum) * 100) : 100

            return PowerState(onAC: state == (kIOPSACPowerValue as String),
                              percentage: percentage,
                              lowPowerMode: lowPower,
                              hasBattery: true)
        }

        return PowerState(onAC: true, percentage: 100, lowPowerMode: lowPower, hasBattery: false)
    }
}
