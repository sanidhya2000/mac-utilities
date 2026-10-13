import Foundation
import AppKit
import Combine
import PowerCore

/// Why a session ended — shown when the user gets back.
enum EndReason: String, Codable {
    case unlocked        = "you came back"
    case workFinished    = "the work finished"
    case timerExpired    = "the timer ran out"
    case batteryLow      = "the battery ran low"
    case maxDuration     = "the safety limit was reached"
    case cancelled       = "you cancelled it"
}

/// A completed session, kept so the user can see what happened while away.
struct SessionReport: Codable {
    let startedAt: Date
    let endedAt: Date
    let endReason: EndReason
    /// Distinct apps seen working during the session.
    let appsSeen: [String]
    /// Whether anything was still working when the session ended.
    let busyAtEnd: Bool

    var duration: TimeInterval { endedAt.timeIntervalSince(startedAt) }
}

enum SessionState: Equatable {
    case idle
    /// Holding sleep with the screen locked.
    case armed(since: Date)
    /// Work-finished mode: nothing busy, counting down before releasing.
    case winding(secondsLeft: Int)

    var isActive: Bool {
        if case .idle = self { return false }
        return true
    }
}

/// Runs an away session: locks the Mac, holds system sleep, and releases on
/// whichever condition the user chose — always with a safety ceiling.
@MainActor
final class AwaySession: ObservableObject {

    @Published private(set) var state: SessionState = .idle
    @Published private(set) var busyApps: [BusyApp] = []
    @Published private(set) var lastReport: SessionReport?
    @Published private(set) var powerState: PowerState = BatteryMonitor.current()
    /// Set when a session ended for a reason the user should see on return.
    @Published var pendingReport: SessionReport?

    private let sleep = SleepController()
    private let monitor = ActivityMonitor()

    private var timer: Timer?
    private var startedAt: Date?
    private var quietSince: Date?
    private var appsSeen: Set<String> = []
    private var armedMode: ReleaseMode = .onUnlock
    private var timerDeadline: Date?

    private let tickInterval: TimeInterval = 5

    /// Arms everything except the screen lock. Used by `--dry-run` so the hold
    /// can be proven on a machine without locking the user out of it.
    var suppressLockForDryRun = false

    // MARK: - Arming

    func arm() {
        guard !state.isActive else { return }

        // Refuse rather than arm a session that must immediately stand down.
        if let reason = powerState.blockedReason(Prefs.shared.powerPolicy) {
            Log.error("refusing to arm: \(reason)")
            NSSound.beep()
            presentBlocked(reason: reason)
            return
        }

        armedMode = Prefs.shared.releaseMode
        startedAt = Date()
        quietSince = nil
        appsSeen = []
        monitor.reset()

        if armedMode == .timer {
            timerDeadline = Date().addingTimeInterval(Double(Prefs.shared.timerMinutes) * 60)
        } else {
            timerDeadline = nil
        }

        if Prefs.shared.allowLidClosed && !ClamshellController.isDisabled {
            ClamshellController.enable()
        }

        sleep.hold(reason: holdReason(), keepScreenOn: false)
        state = .armed(since: startedAt!)

        observeUnlock()
        timer = Timer.scheduledTimer(withTimeInterval: tickInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        timer?.tolerance = 1

        // Lock last: everything must already be holding before the screen goes,
        // otherwise there is a window where the Mac could idle to sleep.
        if Prefs.shared.lockOnArm && !suppressLockForDryRun {
            ScreenLock.lock()
            if Prefs.shared.sleepDisplayOnArm {
                // Give the lock a moment to take before darkening the display.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    ScreenLock.sleepDisplay()
                }
            }
        }
        Log.info("armed — \(armedMode.rawValue)")
    }

    func cancel() { end(reason: .cancelled) }

    // MARK: - Loop

    private func tick() {
        guard state.isActive, let startedAt else { return }

        powerState = BatteryMonitor.current()

        // Safety ceiling first: nothing may keep a Mac awake forever.
        if Date().timeIntervalSince(startedAt) > Double(Prefs.shared.maxHours) * 3600 {
            end(reason: .maxDuration)
            return
        }

        if powerState.blockedReason(Prefs.shared.powerPolicy) != nil {
            end(reason: .batteryLow)
            return
        }

        if let timerDeadline, Date() >= timerDeadline {
            end(reason: .timerExpired)
            return
        }

        busyApps = monitor.tick(Prefs.shared.activityThresholds)
        appsSeen.formUnion(busyApps.map(\.display))

        let working = !busyApps.isEmpty || !monitor.assertingApps.isEmpty
        sleep.hold(reason: holdReason(), keepScreenOn: false)

        guard armedMode == .whenWorkFinishes else {
            state = .armed(since: startedAt)
            return
        }

        if working {
            quietSince = nil
            state = .armed(since: startedAt)
            return
        }

        // Nothing busy: run the grace period before giving up the hold, so a
        // gap between two build steps does not end the session early.
        let since = quietSince ?? Date()
        quietSince = since
        let remaining = Double(Prefs.shared.graceSeconds) - Date().timeIntervalSince(since)

        if remaining <= 0 {
            end(reason: .workFinished)
        } else {
            state = .winding(secondsLeft: Int(remaining.rounded(.up)))
        }
    }

    private func holdReason() -> String {
        guard !busyApps.isEmpty else { return "AFK - locked, waiting" }
        let first = busyApps[0].display
        return busyApps.count == 1
            ? "AFK - \(first) is working"
            : "AFK - \(first) and \(busyApps.count - 1) more are working"
    }

    // MARK: - Ending

    private func end(reason: EndReason) {
        guard let startedAt else { return }

        timer?.invalidate()
        timer = nil
        sleep.release()

        // Lid-closed override is global state; always put it back.
        if Prefs.shared.allowLidClosed && ClamshellController.isDisabled {
            ClamshellController.disable()
        }

        let report = SessionReport(
            startedAt: startedAt,
            endedAt: Date(),
            endReason: reason,
            appsSeen: appsSeen.sorted(),
            busyAtEnd: !busyApps.isEmpty
        )
        lastReport = report
        // A session the user did not personally end is worth surfacing.
        if reason != .cancelled && reason != .unlocked { pendingReport = report }

        self.startedAt = nil
        quietSince = nil
        busyApps = []
        state = .idle
        Log.info("session ended — \(reason.rawValue)")
    }

    private func presentBlocked(reason: String) {
        let alert = NSAlert()
        alert.messageText = "Can't go AFK right now"
        alert.informativeText = "\(reason.prefix(1).uppercased() + reason.dropFirst()). "
            + "Plug in or adjust the battery floor in Settings."
        alert.alertStyle = .warning
        alert.runModal()
    }

    // MARK: - Unlock

    private var observing = false

    /// Coming back is the default end condition, so the unlock notification is
    /// the main signal this class waits on.
    private func observeUnlock() {
        guard !observing else { return }
        observing = true

        DistributedNotificationCenter.default().addObserver(
            forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.state.isActive else { return }
                // Only onUnlock ends here; the other modes deliberately keep
                // holding so a quick check-in does not kill a running job.
                if self.armedMode == .onUnlock { self.end(reason: .unlocked) }
            }
        }
    }

    /// Releases everything on quit so the Mac is never left unable to sleep.
    func shutdown() {
        timer?.invalidate()
        sleep.release()
        if Prefs.shared.allowLidClosed && ClamshellController.isDisabled {
            ClamshellController.disable()
        }
    }
}
