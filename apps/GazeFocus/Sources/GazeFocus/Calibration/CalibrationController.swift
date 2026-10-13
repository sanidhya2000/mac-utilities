import Foundation
import AppKit
import SwiftUI
import CoreGraphics

/// Runs the follow-the-dot calibration across every display.
///
/// Five points per screen: centre plus four inset corners. Corners are inset
/// rather than flush to the edge because people rarely turn far enough to look
/// at a true corner, and a target nobody actually looks at poisons the fit.
@MainActor
final class CalibrationController: ObservableObject {

    /// Fractional positions within each display.
    private static let targets: [(x: Double, y: Double)] = [
        (0.50, 0.50), (0.12, 0.12), (0.88, 0.12), (0.12, 0.88), (0.88, 0.88),
    ]

    /// Samples are averaged over this window once the dot has settled.
    private static let dwell: TimeInterval = 1.6
    private static let settleBeforeSampling: TimeInterval = 0.7

    @Published private(set) var isRunning = false
    @Published private(set) var currentScreenName = ""
    @Published private(set) var progress = 0.0
    /// Live feedback so the user can tell their face is actually being seen.
    @Published private(set) var faceVisible = false

    private var windows: [NSWindow] = []
    private let camera = CameraCapture()
    private let tracker = HeadPoseTracker()

    private var collected: [CalibrationSample] = []
    private var poseBuffer: [HeadPose] = []
    private var isSampling = false
    private var latestPose: HeadPose?

    private var onFinish: ((Bool, String?) -> Void)?

    func start(completion: @escaping (Bool, String?) -> Void) {
        guard !isRunning else { return }
        guard CameraCapture.authorizationStatus() == .authorized else {
            completion(false, "Camera access is required.")
            return
        }

        Log.info("calibration: start() called")
        onFinish = completion
        isRunning = true
        collected = []

        tracker.onPose = { [weak self] pose in
            Task { @MainActor in self?.receive(pose: pose) }
        }
        camera.onFrame = { [weak self] buffer in self?.tracker.process(buffer) }
        camera.onError = { [weak self] message in
            Task { @MainActor in self?.finish(success: false, message: message) }
        }
        camera.start(deviceID: Prefs.shared.cameraID)

        presentWindows()
        Task { await runSequence() }
    }

    func cancel() { finish(success: false, message: nil) }

    private func receive(pose: HeadPose?) {
        faceVisible = pose != nil
        latestPose = pose
        guard isSampling, let pose else { return }
        poseBuffer.append(pose)
    }

    /// One fullscreen black window per display; the dot moves within whichever
    /// screen is being calibrated while the others stay dim.
    private func presentWindows() {
        Log.info("calibration: presenting \(NSScreen.screens.count) fullscreen windows")
        for screen in NSScreen.screens {
            let window = NSWindow(contentRect: screen.frame,
                                  styleMask: [.borderless],
                                  backing: .buffered, defer: false, screen: screen)
            window.level = .screenSaver
            window.backgroundColor = .black
            window.isOpaque = true
            window.ignoresMouseEvents = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

            let view = CalibrationScreenView(controller: self,
                                             screenID: FocusSwitcher.key(for: screen))
            window.contentView = NSHostingView(rootView: view)
            window.setFrame(screen.frame, display: true)
            window.orderFrontRegardless()
            windows.append(window)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Which screen+point is live, so only one window draws the dot.
    @Published private(set) var activeScreenID: String = ""
    @Published private(set) var dotPosition: CGPoint = .zero
    @Published private(set) var dotIsSampling = false

    private func runSequence() async {
        let screens = NSScreen.screens
        let totalSteps = screens.count * Self.targets.count
        var step = 0

        for screen in screens {
            currentScreenName = screen.localizedName
            activeScreenID = FocusSwitcher.key(for: screen)
            let globalFrame = FocusSwitcher.globalFrame(of: screen)

            for target in Self.targets {
                guard isRunning else { return }

                // Position within the window's own coordinate space.
                dotPosition = CGPoint(x: target.x * screen.frame.width,
                                      y: target.y * screen.frame.height)
                dotIsSampling = false

                try? await Task.sleep(for: .seconds(Self.settleBeforeSampling))
                guard isRunning else { return }

                poseBuffer = []
                isSampling = true
                dotIsSampling = true
                try? await Task.sleep(for: .seconds(Self.dwell))
                isSampling = false
                dotIsSampling = false

                guard isRunning else { return }
                record(target: target, globalFrame: globalFrame)

                step += 1
                progress = Double(step) / Double(totalSteps)
            }
        }

        finalize()
    }

    /// Averages the dwell window, discarding the noisiest readings.
    private func record(target: (x: Double, y: Double), globalFrame: CGRect) {
        guard poseBuffer.count >= 4 else {
            Log.error("too few poses for target \(target)")
            return
        }

        // Trim outliers by yaw before averaging: blinks and micro-glances away
        // from the dot show up as extremes.
        let sorted = poseBuffer.sorted { $0.yaw < $1.yaw }
        let trim = sorted.count / 6
        let kept = Array(sorted.dropFirst(trim).dropLast(trim))
        guard !kept.isEmpty else { return }

        var features = [Double](repeating: 0, count: HeadPose.featureCount)
        for pose in kept {
            for (index, value) in pose.features.enumerated() { features[index] += value }
        }
        features = features.map { $0 / Double(kept.count) }
        let area = kept.reduce(0) { $0 + $1.area } / Double(kept.count)

        collected.append(CalibrationSample(
            features: features,
            targetX: globalFrame.minX + target.x * globalFrame.width,
            targetY: globalFrame.minY + target.y * globalFrame.height,
            area: area
        ))
    }

    private func finalize() {
        guard collected.count >= HeadPose.featureCount else {
            finish(success: false, message: "Not enough of your face was visible. Try again with more light.")
            return
        }

        CalibrationStore.shared.replace(with: collected)
        guard let model = CalibrationStore.shared.model else {
            finish(success: false, message: "Calibration could not be solved. Try again.")
            return
        }

        // A very loose fit means the readings carried no usable signal — most
        // often a fixed head with only the eyes moving, which cannot be tracked.
        if model.meanError > 1200 {
            CalibrationStore.shared.clear()
            finish(success: false,
                   message: "Readings were too inconsistent. Try turning your head a little more toward each dot.")
            return
        }

        finish(success: true, message: nil)
    }

    private func finish(success: Bool, message: String?) {
        isRunning = false
        camera.stop()
        tracker.reset()
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        onFinish?(success, message)
        onFinish = nil
    }
}
