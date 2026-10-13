import Foundation
import AppKit
import Combine
import PowerCore

enum EngineStatus: Equatable {
    /// Nothing is working; the Mac may sleep on its normal schedule.
    case idle
    /// Work detected, sleep held.
    case holding(apps: [String])
    /// Work stopped; counting down before releasing the hold.
    case winding(secondsLeft: Int)
    /// Holding is suppressed by battery or Low Power Mode.
    case blocked(reason: String)
    /// User switched WakeHold off from the menu.
    case paused

    var holdsSleep: Bool {
        switch self {
        case .holding, .winding: return true
        case .idle, .blocked, .paused: return false
        }
    }
}

/// Drives the sample → decide → assert loop.
@MainActor
final class WakeEngine: ObservableObject {

    @Published private(set) var status: EngineStatus = .idle
    @Published private(set) var busyApps: [BusyApp] = []
    @Published private(set) var assertingApps: [String] = []
    @Published private(set) var powerState: PowerState = BatteryMonitor.current()

    var isPaused = false { didSet { isPaused ? pause() : resume() } }

    private let monitor = ActivityMonitor()
    private let sleep = SleepController()
    private var timer: Timer?

    /// When work last stopped — the anchor for the grace countdown.
    private var quietSince: Date?

    private let interval: TimeInterval = 2

    func start() {
        observeSystemSleep()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        timer?.tolerance = 0.5
        tick()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        sleep.release()
    }

    private func pause() {
        sleep.release()
        quietSince = nil
        status = .paused
    }

    private func resume() {
        monitor.reset()
        status = .idle
        tick()
    }

    private func tick() {
        guard !isPaused else { return }

        powerState = BatteryMonitor.current()
        busyApps = monitor.tick(Prefs.shared.activityThresholds)
        assertingApps = monitor.assertingApps

        if let reason = powerState.blockedReason(Prefs.shared.powerPolicy) {
            sleep.release()
            quietSince = nil
            status = .blocked(reason: reason)
            return
        }

        let working = !busyApps.isEmpty || !assertingApps.isEmpty
        if working {
            quietSince = nil
            let names = busyApps.map(\.display) + assertingApps
            sleep.hold(reason: holdReason(for: names), keepScreenOn: Prefs.shared.keepScreenOn)
            status = .holding(apps: names)
            return
        }

        // Work stopped — run the grace period before letting go, so a gap
        // between two build steps does not drop the hold mid-job.
        let startedQuiet = quietSince ?? Date()
        quietSince = startedQuiet

        let remaining = Double(Prefs.shared.graceSeconds) - Date().timeIntervalSince(startedQuiet)
        if remaining > 0 {
            sleep.hold(reason: "waiting for work to resume", keepScreenOn: Prefs.shared.keepScreenOn)
            status = .winding(secondsLeft: Int(remaining.rounded(.up)))
        } else {
            sleep.release()
            status = .idle
        }
    }

    private func holdReason(for names: [String]) -> String {
        guard let first = names.first else { return "work in progress" }
        return names.count == 1 ? "\(first) is working"
                                : "\(first) and \(names.count - 1) more are working"
    }

    /// Sampling across a sleep/wake boundary would show a huge fake delta, so
    /// the baseline is thrown away and rebuilt on wake.
    private func observeSystemSleep() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.willSleepNotification,
                           object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.sleep.release() }
        }
        center.addObserver(forName: NSWorkspace.didWakeNotification,
                           object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.monitor.reset()
                self?.quietSince = nil
            }
        }
    }

    /// Re-evaluates immediately, so toggling an app in the menu takes effect
    /// without waiting for the next sampling interval.
    func refresh() { tick() }
}
