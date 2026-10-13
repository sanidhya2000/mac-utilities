import Foundation

/// UserDefaults-backed settings. Defaults mirror the behaviour described on the
/// original product page: a 2-minute grace period, a 20% battery floor, and
/// system sleep held without forcing the display to stay on.
final class Prefs {
    static let shared = Prefs()
    private let defaults = UserDefaults.standard

    private enum Key {
        static let graceSeconds      = "graceSeconds"
        static let batteryThreshold  = "batteryThreshold"
        static let respectLowPower   = "respectLowPower"
        static let allowLidClosed    = "allowLidClosed"
        static let keepScreenOn      = "keepScreenOn"
        static let ignoredApps       = "ignoredApps"
        static let cpuThreshold      = "cpuThresholdPercent"
        static let diskThreshold     = "diskThresholdKBps"
        static let netThreshold      = "netThresholdKBps"
        static let sustainSeconds    = "sustainSeconds"
        static let honorAppAssertions = "honorAppAssertions"
        static let launchAtLogin     = "launchAtLogin"
        static let verbose           = "verbose"
    }

    private init() {
        defaults.register(defaults: [
            Key.graceSeconds: 120,
            Key.batteryThreshold: 20,
            Key.respectLowPower: true,
            Key.allowLidClosed: false,
            Key.keepScreenOn: false,
            Key.ignoredApps: [String](),
            Key.cpuThreshold: 15.0,
            Key.diskThreshold: 500.0,
            Key.netThreshold: 100.0,
            Key.sustainSeconds: 10,
            Key.honorAppAssertions: true,
            Key.launchAtLogin: false,
            Key.verbose: false,
        ])
    }

    /// How long work must be quiet before sleep is released. Clamped to the
    /// 30s–10min range the settings UI exposes.
    var graceSeconds: Int {
        get { min(600, max(30, defaults.integer(forKey: Key.graceSeconds))) }
        set { defaults.set(newValue, forKey: Key.graceSeconds) }
    }

    var batteryThreshold: Int {
        get { defaults.integer(forKey: Key.batteryThreshold) }
        set { defaults.set(newValue, forKey: Key.batteryThreshold) }
    }

    var respectLowPower: Bool {
        get { defaults.bool(forKey: Key.respectLowPower) }
        set { defaults.set(newValue, forKey: Key.respectLowPower) }
    }

    var allowLidClosed: Bool {
        get { defaults.bool(forKey: Key.allowLidClosed) }
        set { defaults.set(newValue, forKey: Key.allowLidClosed) }
    }

    var keepScreenOn: Bool {
        get { defaults.bool(forKey: Key.keepScreenOn) }
        set { defaults.set(newValue, forKey: Key.keepScreenOn) }
    }

    /// Bundle identifiers, or bare executable names for command-line tools.
    var ignoredApps: Set<String> {
        get { Set(defaults.stringArray(forKey: Key.ignoredApps) ?? []) }
        set { defaults.set(Array(newValue).sorted(), forKey: Key.ignoredApps) }
    }

    var cpuThreshold: Double {
        get { defaults.double(forKey: Key.cpuThreshold) }
        set { defaults.set(newValue, forKey: Key.cpuThreshold) }
    }

    var diskThresholdKBps: Double {
        get { defaults.double(forKey: Key.diskThreshold) }
        set { defaults.set(newValue, forKey: Key.diskThreshold) }
    }

    var netThresholdKBps: Double {
        get { defaults.double(forKey: Key.netThreshold) }
        set { defaults.set(newValue, forKey: Key.netThreshold) }
    }

    /// Activity must persist this long before it counts, so a brief spike from
    /// opening a file or loading a page never holds the machine awake.
    var sustainSeconds: Int {
        get { max(1, defaults.integer(forKey: Key.sustainSeconds)) }
        set { defaults.set(newValue, forKey: Key.sustainSeconds) }
    }

    /// Whether another app's own "don't sleep" power assertion counts as work.
    var honorAppAssertions: Bool {
        get { defaults.bool(forKey: Key.honorAppAssertions) }
        set { defaults.set(newValue, forKey: Key.honorAppAssertions) }
    }

    var launchAtLogin: Bool {
        get { defaults.bool(forKey: Key.launchAtLogin) }
        set { defaults.set(newValue, forKey: Key.launchAtLogin) }
    }

    var verbose: Bool {
        get { defaults.bool(forKey: Key.verbose) }
        set { defaults.set(newValue, forKey: Key.verbose) }
    }
}
