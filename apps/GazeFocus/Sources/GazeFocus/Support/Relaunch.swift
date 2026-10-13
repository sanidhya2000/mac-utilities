import Foundation
import AppKit

/// Quits and reopens the app.
///
/// macOS frequently will not let a *running* process see an Accessibility grant
/// made after it launched — the permission shows as enabled in System Settings
/// while `AXIsProcessTrusted()` keeps returning false. A relaunch is the only
/// reliable remedy, so it is offered as a button rather than left for the user
/// to work out.
enum Relaunch {
    static func now() {
        let path = Bundle.main.bundlePath

        // Reopening has to outlive this process, so hand it to a detached
        // shell that waits for us to exit first.
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 1; /usr/bin/open -n \"\(path)\""]

        do {
            try task.run()
        } catch {
            Log.error("relaunch failed: \(error.localizedDescription)")
            return
        }
        NSApp.terminate(nil)
    }
}
