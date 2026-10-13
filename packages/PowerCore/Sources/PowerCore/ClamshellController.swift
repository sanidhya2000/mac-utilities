import Foundation
import AppKit

/// Lid-closed operation.
///
/// Keeping a MacBook awake with the lid shut means clearing the clamshell-sleep
/// flag, which only root can do — hence the one-time administrator prompt. The
/// flag is global and survives this process, so it is paired with a watchdog
/// that restores it if WakeHold ever goes away without cleaning up.
public enum ClamshellController {

    /// Set by the owning app so the watchdog and its label are not hardcoded
    /// to one product.
    public static var ownerProcessName = ProcessInfo.processInfo.processName
    public static var watchdogLabel = "com.powercore.clamshell-watchdog"
    static var watchdogURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(watchdogLabel).plist")
    }

    public static var isDisabled: Bool {
        guard let output = run("/usr/bin/pmset", ["-g"]) else { return false }
        // `SleepDisabled 1` appears in pmset's settings dump when the flag is set.
        return output.contains("SleepDisabled") && output.contains("SleepDisabled\t1")
            || output.range(of: #"SleepDisabled\s+1"#, options: .regularExpression) != nil
    }

    /// Prompts for administrator rights once, then clears clamshell sleep and
    /// installs the watchdog. Returns false if the user cancels the prompt.
    @discardableResult
    public static func enable() -> Bool {
        guard runPrivileged("pmset -a disablesleep 1") else { return false }
        installWatchdog()
        Log.info("clamshell sleep disabled")
        return true
    }

    /// Restores normal lid-closed sleep and removes the watchdog.
    @discardableResult
    public static func disable() -> Bool {
        removeWatchdog()
        let ok = runPrivileged("pmset -a disablesleep 0")
        if ok { Log.info("clamshell sleep restored") }
        return ok
    }

    /// A LaunchAgent that restores clamshell sleep at every login. If WakeHold
    /// crashes while the lid flag is set, the next login puts it back rather
    /// than leaving the Mac unable to sleep.
    private static func installWatchdog() {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
          <key>Label</key><string>\(watchdogLabel)</string>
          <key>ProgramArguments</key>
          <array>
            <string>/bin/sh</string><string>-c</string>
            <string>pgrep -x \(ownerProcessName) >/dev/null || /usr/bin/pmset -a disablesleep 0</string>
          </array>
          <key>RunAtLoad</key><true/>
          <key>StartInterval</key><integer>60</integer>
        </dict></plist>
        """
        do {
            try FileManager.default.createDirectory(
                at: watchdogURL.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            try plist.write(to: watchdogURL, atomically: true, encoding: .utf8)
            _ = run("/bin/launchctl", ["load", "-w", watchdogURL.path])
        } catch {
            Log.error("watchdog install failed: \(error.localizedDescription)")
        }
    }

    private static func removeWatchdog() {
        guard FileManager.default.fileExists(atPath: watchdogURL.path) else { return }
        _ = run("/bin/launchctl", ["unload", "-w", watchdogURL.path])
        try? FileManager.default.removeItem(at: watchdogURL)
    }

    /// Escalates via AppleScript, which shows the standard macOS admin prompt.
    /// A signed build should prefer an SMAppService helper; this route is used
    /// because it needs no Developer ID to work.
    private static func runPrivileged(_ command: String) -> Bool {
        let escaped = command.replacingOccurrences(of: "\"", with: "\\\"")
        let source = "do shell script \"\(escaped)\" with administrator privileges"

        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return false }
        script.executeAndReturnError(&error)

        if let error {
            // -128 is the user clicking Cancel, which is not a failure to report.
            let code = error[NSAppleScript.errorNumber] as? Int ?? 0
            if code != -128 { Log.error("privileged command failed: \(error)") }
            return false
        }
        return true
    }

    @discardableResult
    private static func run(_ path: String, _ arguments: [String]) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = arguments
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do { try task.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }
}
