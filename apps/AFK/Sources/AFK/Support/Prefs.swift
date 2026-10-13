import Foundation
import PowerCore

/// How an armed session should end.
enum ReleaseMode: String, CaseIterable, Codable {
    /// Hold until the user comes back and unlocks. The default: predictable,
    /// and never cuts a job short by guessing how long it needs.
    case onUnlock
    /// Hold until nothing is working any more, then let the Mac sleep.
    case whenWorkFinishes
    /// Hold for a fixed stretch.
    case timer

    var label: String {
        switch self {
        case .onUnlock:         return "Until I unlock"
        case .whenWorkFinishes: return "Until the work finishes"
        case .timer:            return "For a set time"
        }
    }
}

final class Prefs {
    static let shared = Prefs()
    private let defaults = UserDefaults.standard

    private enum Key {
        static let releaseMode    = "releaseMode"
        static let timerMinutes   = "timerMinutes"
        static let maxHours       = "maxHours"
        static let batteryFloor   = "batteryFloor"
        static let respectLowPower = "respectLowPower"
        static let allowLidClosed = "allowLidClosed"
        static let lockOnArm      = "lockOnArm"
        static let sleepDisplay   = "sleepDisplayOnArm"
        static let graceSeconds   = "graceSeconds"
        static let launchAtLogin  = "launchAtLogin"
    }

    private init() {
        defaults.register(defaults: [
            Key.releaseMode: ReleaseMode.onUnlock.rawValue,
            Key.timerMinutes: 60,
            Key.maxHours: 12,
            Key.batteryFloor: 20,
            Key.respectLowPower: true,
            Key.allowLidClosed: false,
            Key.lockOnArm: true,
            Key.sleepDisplay: true,
            Key.graceSeconds: 120,
            Key.launchAtLogin: false,
        ])
    }

    var releaseMode: ReleaseMode {
        get { ReleaseMode(rawValue: defaults.string(forKey: Key.releaseMode) ?? "") ?? .onUnlock }
        set { defaults.set(newValue.rawValue, forKey: Key.releaseMode) }
    }

    var timerMinutes: Int {
        get { max(5, defaults.integer(forKey: Key.timerMinutes)) }
        set { defaults.set(newValue, forKey: Key.timerMinutes) }
    }

    /// A hard ceiling on any session, so a forgotten AFK cannot keep a Mac
    /// awake indefinitely.
    var maxHours: Int {
        get { max(1, defaults.integer(forKey: Key.maxHours)) }
        set { defaults.set(newValue, forKey: Key.maxHours) }
    }

    var batteryFloor: Int {
        get { defaults.integer(forKey: Key.batteryFloor) }
        set { defaults.set(newValue, forKey: Key.batteryFloor) }
    }

    var respectLowPower: Bool {
        get { defaults.bool(forKey: Key.respectLowPower) }
        set { defaults.set(newValue, forKey: Key.respectLowPower) }
    }

    var allowLidClosed: Bool {
        get { defaults.bool(forKey: Key.allowLidClosed) }
        set { defaults.set(newValue, forKey: Key.allowLidClosed) }
    }

    var lockOnArm: Bool {
        get { defaults.bool(forKey: Key.lockOnArm) }
        set { defaults.set(newValue, forKey: Key.lockOnArm) }
    }

    var sleepDisplayOnArm: Bool {
        get { defaults.bool(forKey: Key.sleepDisplay) }
        set { defaults.set(newValue, forKey: Key.sleepDisplay) }
    }

    /// Quiet period before a work-finished session gives up the hold.
    var graceSeconds: Int {
        get { max(30, defaults.integer(forKey: Key.graceSeconds)) }
        set { defaults.set(newValue, forKey: Key.graceSeconds) }
    }

    var launchAtLogin: Bool {
        get { defaults.bool(forKey: Key.launchAtLogin) }
        set { defaults.set(newValue, forKey: Key.launchAtLogin) }
    }

    var powerPolicy: PowerPolicy {
        // The display is never force-lit: a locked Mac should be dark.
        PowerPolicy(batteryFloor: batteryFloor,
                    respectLowPowerMode: respectLowPower,
                    keepScreenOn: false)
    }

    var activityThresholds: ActivityThresholds {
        ActivityThresholds(sustainSeconds: 8)
    }
}
