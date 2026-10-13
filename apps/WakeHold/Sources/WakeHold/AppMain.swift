import SwiftUI
import AppKit
import PowerCore

@main
struct WakeHoldApp {
    static func main() {
        Log.subsystem = "com.wakehold.app"
        ClamshellController.ownerProcessName = "WakeHold"
        ClamshellController.watchdogLabel = "com.wakehold.clamshell-watchdog"

        // A diagnostic sweep for the terminal: no UI, prints what the engine
        // sees and exits. Useful when someone reports "it isn't holding".
        if CommandLine.arguments.contains("--diagnose") {
            Prefs.shared.verbose = true
            Diagnostics.run()
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
    private var engine: WakeEngine?
    private var menuBar: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let engine = WakeEngine()
        self.engine = engine
        self.menuBar = MenuBarController(engine: engine)
        engine.start()
        Log.info("WakeHold started")
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Releasing the assertion here is what guarantees quitting the app
        // always restores normal sleep.
        engine?.stop()
    }
}
