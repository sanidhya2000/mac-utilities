import SwiftUI
import AppKit
import PowerCore

@main
struct AFKApp {
    static func main() {
        Log.subsystem = "com.afkapp.mac"
        ClamshellController.ownerProcessName = "AFK"
        ClamshellController.watchdogLabel = "com.afkapp.clamshell-watchdog"

        if let index = CommandLine.arguments.firstIndex(of: "--dry-run") {
            let seconds = CommandLine.arguments.count > index + 1
                ? Int(CommandLine.arguments[index + 1]) ?? 20 : 20
            MainActor.assumeIsolated { DryRun.run(seconds: seconds) }
            return
        }

        if CommandLine.arguments.contains("--diagnose") {
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
    private var session: AwaySession?
    private var menuBar: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let session = AwaySession()
        self.session = session
        self.menuBar = MenuBarController(session: session)
        Log.info("AFK started")
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Quitting must always restore normal sleep behaviour.
        session?.shutdown()
    }
}
