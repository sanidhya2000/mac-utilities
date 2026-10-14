import SwiftUI
import AppKit

@main
struct GazeFocusApp {
    static func main() {
        if let index = CommandLine.arguments.firstIndex(of: "--probe-camera") {
            let seconds = CommandLine.arguments.count > index + 1
                ? Int(CommandLine.arguments[index + 1]) ?? 8 : 8
            MainActor.assumeIsolated { CameraProbe.run(seconds: seconds) }
            return
        }

        if CommandLine.arguments.contains("--diagnose") {
            // main() already runs on the main thread; this just tells the
            // compiler so, without spinning up a run loop.
            MainActor.assumeIsolated { Diagnostics.run() }
            return
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var engine: GazeEngine?
    private var calibration: CalibrationController?
    private var menuBar: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let engine = GazeEngine()
        let calibration = CalibrationController()
        let menuBar = MenuBarController(engine: engine, calibration: calibration)

        self.engine = engine
        self.calibration = calibration
        self.menuBar = menuBar

        engine.start()

        // Anything unfinished — permissions or calibration — opens setup.
        switch engine.status {
        case .needsCamera, .needsAccessibility, .needsCalibration:
            menuBar.openOnboarding()
        default:
            break
        }
        Log.info("GazeFocus started")
    }

    /// Opening the app while it is already running reveals its controls.
    ///
    /// Menu bar icons are not guaranteed to be reachable: with enough of them
    /// macOS hides the overflow, and on a notched Mac they disappear behind
    /// the notch entirely. Without this, the app is running, using the camera,
    /// and impossible to reach — the user cannot even quit it.
    func applicationShouldHandleReopen(_ sender: NSApplication,
                                       hasVisibleWindows: Bool) -> Bool {
        menuBar?.revealControls()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        engine?.stop()
    }
}
