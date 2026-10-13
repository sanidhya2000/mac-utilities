import Foundation
import AppKit
import Combine
import CoreGraphics
import GazeCore

enum GazeStatus: Equatable {
    case needsCamera
    case needsAccessibility
    case needsCalibration
    case paused
    case noFace
    /// Tracking, with the display name currently being looked at.
    case tracking(screen: String)
    /// Suppressed for a transient reason: typing, pointer in use, locked.
    case waiting(reason: String)
}

/// Drives the camera → pose → gaze point → focus pipeline.
@MainActor
final class GazeEngine: ObservableObject {

    @Published private(set) var status: GazeStatus = .needsCamera
    @Published private(set) var gazePoint: CGPoint?
    /// Mean calibration error in points, surfaced in settings as fit quality.
    @Published private(set) var fitError: Double?
    /// Set when the user has moved noticeably closer or further than they
    /// calibrated at, which is the main cause of accuracy quietly degrading.
    @Published private(set) var needsRecalibration = false

    var isPaused = false {
        didSet { isPaused ? handlePause() : handleResume() }
    }

    private let camera = CameraCapture()
    private let tracker = HeadPoseTracker()
    private let switcher = FocusSwitcher()
    private let panes = PaneFocuser()
    private let guards = InputGuards()
    private let store = CalibrationStore.shared

    /// The candidate the gaze is resting on, and since when — the settle timer.
    private var candidateScreen: NSScreen?
    private var candidateSince: Date?
    private var candidateGaze: CGPoint = .zero

    /// Currently focused screen, so unchanged gaze does no work.
    private var activeScreenKey: String?

    private var lastPaneSwitch = Date.distantPast
    private var lastPose: HeadPose?
    private var screenLocked = false
    private var driftSamples: [Double] = []

    private var cancellables: Set<AnyCancellable> = []
    private var permissionWatcher: Timer?

    /// A click further than this from the predicted gaze is treated as the
    /// user clicking without looking, and is not learned from.
    private static let maxLearningDisagreement: Double = 700

    // MARK: - Lifecycle

    func start() {
        guards.onClick = { [weak self] point in self?.learn(from: point) }
        observeSystemState()
        startPermissionWatcher()
        refreshStatus()

        guard canRun else { return }
        startPipeline()
    }

    func stop() {
        permissionWatcher?.invalidate()
        permissionWatcher = nil
        camera.stop()
        guards.stop()
        tracker.reset()
        isPipelineLive = false
    }

    func restartCamera() {
        camera.stop()
        tracker.reset()
        camera.start(deviceID: Prefs.shared.cameraID)
    }

    private var canRun: Bool {
        CameraCapture.authorizationStatus() == .authorized
            && Accessibility.isTrusted
            && store.isCalibrated
    }

    /// True once the pipeline is actually consuming frames.
    private var isPipelineLive = false

    /// Permissions can be granted or revoked at any time, and macOS offers no
    /// notification for either. Without this poll the normal setup flow —
    /// launch, go to System Settings, grant, come back — leaves the engine
    /// stuck in `.needsAccessibility` forever, because the only check happened
    /// at launch. Relaunching was the sole workaround.
    private func startPermissionWatcher() {
        guard permissionWatcher == nil else { return }
        permissionWatcher = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reconcilePermissions() }
        }
        permissionWatcher?.tolerance = 0.5
    }

    private func reconcilePermissions() {
        let ready = canRun

        if ready && !isPipelineLive && !isPaused {
            startPipeline()
            return
        }

        // Permission withdrawn mid-session: stop cleanly rather than failing
        // silently on every frame.
        if !ready && isPipelineLive {
            camera.stop()
            tracker.reset()
            gazePoint = nil
            isPipelineLive = false
            Log.info("permissions withdrawn — pipeline stopped")
        }

        if !ready { refreshStatus() }
    }

    /// Wires up and starts the capture pipeline. Safe to call repeatedly.
    private func startPipeline() {
        guard !isPipelineLive else { return }

        camera.onError = { message in Log.error(message) }
        camera.onFrame = { [weak self] buffer in
            // Vision runs on the camera queue; results hop to the main actor.
            self?.tracker.process(buffer)
        }
        tracker.onPose = { [weak self] pose in
            Task { @MainActor in self?.handle(pose: pose) }
        }

        camera.start(deviceID: Prefs.shared.cameraID)
        guards.start()
        isPipelineLive = true
        fitError = store.model?.meanError
        status = .noFace
        Log.info("pipeline started")
    }

    func refreshStatus() {
        if CameraCapture.authorizationStatus() != .authorized { status = .needsCamera; return }
        if !Accessibility.isTrusted { status = .needsAccessibility; return }
        if !store.isCalibrated { status = .needsCalibration; return }
        if isPaused { status = .paused; return }
        // Permissions and calibration are all present; let the pipeline
        // own the status from here.
        switch status {
        case .needsCamera, .needsAccessibility, .needsCalibration:
            status = isPipelineLive ? .noFace : .waiting(reason: "starting")
        default:
            break
        }
    }

    // MARK: - Pipeline

    private func handle(pose: HeadPose?) {
        guard !isPaused, canRun else { return }

        guard let pose else {
            // No face: stop acting, but keep whatever focus the user has.
            gazePoint = nil
            candidateScreen = nil
            candidateSince = nil
            status = .noFace
            return
        }
        lastPose = pose

        guard let model = store.model else { return }

        if screenLocked {
            status = .waiting(reason: "screen locked")
            return
        }

        // A head turned far from any display means the user is talking to
        // someone or reading paper — not choosing a screen.
        guard isFacingScreens(pose) else {
            gazePoint = nil
            candidateSince = nil
            status = .waiting(reason: "looking away")
            return
        }

        trackDrift(pose: pose, model: model)

        // The fit is linear and so extrapolates without limit; a head turned
        // further than anything seen during calibration can predict a point off
        // every display. Clamping keeps it usable for window and pane targeting.
        let screenFrames = NSScreen.screens.map(FocusSwitcher.globalFrame(of:))
        let predicted = ScreenGeometry.clamp(model.predict(pose.features), to: screenFrames)
        gazePoint = predicted

        // System state first: these are the cases where the user is visibly
        // mid-action and a focus change would destroy what they are doing.
        if let reason = SystemGuards.blockingReason() {
            candidateSince = nil
            status = .waiting(reason: reason)
            return
        }

        if guards.isTyping {
            candidateSince = nil
            status = .waiting(reason: "typing")
            return
        }
        if guards.isHoldingModifier {
            // Mid-shortcut: the rest of the chord must reach the same app.
            status = .waiting(reason: "shortcut in progress")
            return
        }
        if guards.isUsingPointer {
            candidateSince = nil
            status = .waiting(reason: "using pointer")
            return
        }

        evaluate(gaze: predicted)
    }

    /// Applies the settle delay and edge margin, then switches.
    private func evaluate(gaze: CGPoint) {
        guard let screen = FocusSwitcher.screen(at: gaze)
                ?? FocusSwitcher.nearestScreen(to: gaze) else { return }

        let screenKey = FocusSwitcher.key(for: screen)
        let frame = FocusSwitcher.globalFrame(of: screen)

        // Inside the edge band the choice of screen is ambiguous; holding still
        // here is what prevents flicker between adjacent displays.
        let margin = Prefs.shared.edgeMargin
        let inEdgeBand = ScreenGeometry.isNearVerticalEdge(gaze, of: frame, margin: margin)
        if inEdgeBand && screenKey != activeScreenKey {
            status = .waiting(reason: "near screen edge")
            return
        }

        if screenKey != candidateScreen.map(FocusSwitcher.key(for:)) {
            candidateScreen = screen
            candidateSince = Date()
            candidateGaze = gaze
            return
        }
        candidateGaze = gaze

        // After a copy, shorten the settle so a paste lands where the user is
        // already looking rather than in the window they copied from.
        var settle = Double(Prefs.shared.settleMilliseconds) / 1000
        if guards.expectsPaste { settle = min(settle, 0.12) }

        guard let since = candidateSince, Date().timeIntervalSince(since) >= settle else { return }

        status = .tracking(screen: screen.localizedName)

        if screenKey != activeScreenKey {
            switchScreen(to: screen, gaze: gaze)
        } else {
            maybeSwitchPane(gaze: gaze)
        }
    }

    private func switchScreen(to screen: NSScreen, gaze: CGPoint) {
        guard let window = switcher.focus(on: screen, gazePoint: gaze) else { return }
        guards.noteOwnCursorWarp()
        activeScreenKey = FocusSwitcher.key(for: screen)
        panes.reset()
        lastPaneSwitch = Date()
        Log.info("focused \(window.ownerName) on \(screen.localizedName)")
    }

    /// Within the same screen, move between windows and split panes.
    private func maybeSwitchPane(gaze: CGPoint) {
        let delay = Double(Prefs.shared.paneDelayMilliseconds) / 1000
        guard Date().timeIntervalSince(lastPaneSwitch) >= delay else { return }

        guard let target = WindowFinder.window(at: gaze) else { return }
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier

        if target.pid != front {
            // Gaze moved to a different window on the same screen.
            guard let screen = FocusSwitcher.screen(at: gaze) else { return }
            switcher.focus(on: screen, gazePoint: gaze)
            guards.noteOwnCursorWarp()
            lastPaneSwitch = Date()
            return
        }

        if panes.focusPane(in: target, at: gaze) {
            lastPaneSwitch = Date()
        }
    }

    private func isFacingScreens(_ pose: HeadPose) -> Bool {
        // turnThreshold is a 0–100 sensitivity; convert to a yaw limit in
        // radians. A higher setting tolerates a wider turn before giving up.
        let limit = 0.5 + Prefs.shared.turnThreshold / 100 * 0.6
        return abs(pose.yaw) < limit && abs(pose.pitch) < limit
    }

    /// Watches for sustained distance change rather than reacting to one frame.
    private func trackDrift(pose: HeadPose, model: GazeModel) {
        driftSamples.append(model.distanceDrift(area: pose.area))
        if driftSamples.count > 150 { driftSamples.removeFirst() }
        guard driftSamples.count == 150 else { return }

        let mean = driftSamples.reduce(0, +) / Double(driftSamples.count)
        needsRecalibration = mean < 0.8 || mean > 1.25
    }

    // MARK: - Learning

    /// Every deliberate click is a free calibration point: the user was almost
    /// certainly looking where they clicked.
    private func learn(from point: CGPoint) {
        guard Prefs.shared.learnFromClicks, !isPaused else { return }
        guard let pose = lastPose, store.isCalibrated else { return }
        // A click while typing is likely a correction, not a considered look.
        guard !guards.isTyping else { return }

        if let window = WindowFinder.window(at: point) {
            switcher.noteManualFocus(window)
        }

        // Only learn from clicks that roughly agree with where the model
        // already thinks the user is looking. People click things they are not
        // looking at constantly — a notification, a menu bar item, a button
        // found by muscle memory — and treating those as ground truth drags the
        // fit away from reality instead of refining it.
        if let model = store.model {
            let predicted = model.predict(pose.features)
            let disagreement = hypot(predicted.x - point.x, predicted.y - point.y)
            guard disagreement < Self.maxLearningDisagreement else {
                Log.info("ignored click \(Int(disagreement))pt from predicted gaze")
                return
            }
        }

        store.append(CalibrationSample(
            features: pose.features,
            targetX: point.x, targetY: point.y,
            area: pose.area
        ))
        fitError = store.model?.meanError

        if let screen = FocusSwitcher.screen(at: point) {
            activeScreenKey = FocusSwitcher.key(for: screen)
        }
    }

    // MARK: - System state

    private func handlePause() {
        camera.stop()
        tracker.reset()
        gazePoint = nil
        isPipelineLive = false
        status = .paused
    }

    private func handleResume() {
        refreshStatus()
        guard canRun else { return }
        tracker.reset()
        startPipeline()
    }

    /// The camera is released whenever the Mac locks or sleeps, so the camera
    /// light never stays on while the user is away.
    private func observeSystemState() {
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(forName: NSWorkspace.willSleepNotification,
                              object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.suspend(locked: true) }
        }
        workspace.addObserver(forName: NSWorkspace.didWakeNotification,
                              object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.unsuspend() }
        }

        let distributed = DistributedNotificationCenter.default()
        distributed.addObserver(forName: .init("com.apple.screenIsLocked"),
                                object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.suspend(locked: true) }
        }
        distributed.addObserver(forName: .init("com.apple.screenIsUnlocked"),
                                object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.unsuspend() }
        }

        // Rearranging displays invalidates the calibration's coordinate space.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.activeScreenKey = nil
                self?.refreshStatus()
            }
        }
    }

    private func suspend(locked: Bool) {
        screenLocked = locked
        camera.stop()
        tracker.reset()
        gazePoint = nil
        isPipelineLive = false
    }

    private func unsuspend() {
        screenLocked = false
        guard !isPaused, canRun else { return }
        startPipeline()
    }

    // MARK: - Calibration handoff

    func currentPose() -> HeadPose? { lastPose }

    func recalibrated() {
        driftSamples.removeAll()
        needsRecalibration = false
        activeScreenKey = nil
        fitError = store.model?.meanError
        refreshStatus()
        if canRun && !isPaused { camera.start(deviceID: Prefs.shared.cameraID) }
    }
}
