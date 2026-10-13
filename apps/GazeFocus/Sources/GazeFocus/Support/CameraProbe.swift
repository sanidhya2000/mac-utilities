import Foundation
import AppKit
import GazeCore

/// Starts the real capture pipeline and reports what arrives.
///
/// Answers the question "is it actually looking?" directly, instead of
/// inferring it from CPU use or log output — both of which can be misleading.
enum CameraProbe {
    @MainActor
    static func run(seconds: Int) {
        setbuf(stdout, nil)
        print("GazeFocus camera probe — \(seconds)s\n")

        let camera = CameraCapture()
        let tracker = HeadPoseTracker()

        var frames = 0
        var poses = 0
        var lastPose: HeadPose?
        let lock = NSLock()

        camera.onError = { print("camera error: \($0)") }
        camera.onFrame = { buffer in
            lock.lock(); frames += 1; lock.unlock()
            tracker.process(buffer)
        }
        tracker.onPose = { pose in
            guard let pose else { return }
            lock.lock(); poses += 1; lastPose = pose; lock.unlock()
        }

        print("starting capture…")
        camera.start(deviceID: Prefs.shared.cameraID)

        let deadline = Date().addingTimeInterval(Double(seconds))
        while Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        camera.stop()

        lock.lock()
        let frameCount = frames, poseCount = poses, pose = lastPose
        lock.unlock()

        let processedFPS = Double(frameCount) / Double(seconds)
        let cameraFPS = Double(camera.framesReceived) / Double(seconds)
        print(String(format: "\ncamera delivers:  %.1f fps", cameraFPS))
        print(String(format: "we process:       %.1f fps  (%d frames)", processedFPS, frameCount))
        print("faces detected:   \(poseCount)")

        if let pose, let model = CalibrationStore.shared.model {
            let screens = NSScreen.screens
            let screenFrames = screens.map(FocusSwitcher.globalFrame(of:))
            let raw = model.predict(pose.features)
            let clamped = ScreenGeometry.clamp(raw, to: screenFrames)

            print(String(format: "last head pose:  yaw %.3f  pitch %.3f  face at (%.2f, %.2f)",
                         pose.yaw, pose.pitch, pose.centerX, pose.centerY))
            print(String(format: "raw prediction:  (%.0f, %.0f)", raw.x, raw.y))
            print(String(format: "after clamping:  (%.0f, %.0f)", clamped.x, clamped.y))

            if let index = ScreenGeometry.frame(containing: clamped, in: screenFrames)
                ?? ScreenGeometry.nearestFrame(to: clamped, in: screenFrames) {
                print("looking at:      \(screens[index].localizedName)")
            }

            // A prediction far outside every display means the fit is
            // extrapolating badly and recalibration would help.
            let offScreen = !screenFrames.contains { $0.contains(raw) }
            if offScreen {
                let drift = ScreenGeometry.nearestFrame(to: raw, in: screenFrames)
                    .map { ScreenGeometry.distance(screenFrames[$0], raw) } ?? 0
                print(String(format: "\nNOTE: raw prediction fell %.0f pt outside every display.",
                             Double(drift)))
                print("      Clamping keeps it usable, but recalibrating would improve accuracy.")
            }
            if model.meanError > 300 {
                print(String(format: "NOTE: calibration error is %.0f pt — recalibrating is recommended.",
                             model.meanError))
            }
        }

        print("")
        if frameCount == 0 {
            print("VERDICT: no frames — the camera never started")
        } else if poseCount == 0 {
            print("VERDICT: frames arrive but no face was found (lighting? camera covered?)")
        } else {
            print("VERDICT: pipeline healthy")
        }
    }
}
