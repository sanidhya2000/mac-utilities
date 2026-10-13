import Foundation
import AppKit
import CoreGraphics
import PowerCore

/// Locks the screen.
///
/// `SACLockScreenImmediate` in login.framework is the route macOS itself uses.
/// It is a private symbol, so it is resolved at runtime and the whole thing
/// degrades to a synthesized ⌃⌘Q if a future OS removes it — rather than
/// failing to build or crashing on launch.
enum ScreenLock {

    private static let frameworkPath =
        "/System/Library/PrivateFrameworks/login.framework/Versions/A/login"

    private typealias LockFunction = @convention(c) () -> Void

    /// Resolved once; nil when the symbol is unavailable on this OS.
    private static let lockFunction: LockFunction? = {
        guard let handle = dlopen(frameworkPath, RTLD_LAZY) else {
            Log.error("login.framework unavailable: \(String(cString: dlerror()))")
            return nil
        }
        guard let symbol = dlsym(handle, "SACLockScreenImmediate") else {
            Log.error("SACLockScreenImmediate not found; will fall back to ⌃⌘Q")
            return nil
        }
        return unsafeBitCast(symbol, to: LockFunction.self)
    }()

    /// True when the fast path is available, so the UI can warn if it is not.
    static var usesSystemLock: Bool { lockFunction != nil }

    @discardableResult
    static func lock() -> Bool {
        if let lockFunction {
            lockFunction()
            Log.info("screen locked via system call")
            return true
        }
        return lockViaShortcut()
    }

    /// ⌃⌘Q is the documented lock shortcut. It only works if the user has not
    /// remapped it, which is exactly why it is the fallback and not the default.
    private static func lockViaShortcut() -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return false }
        let qKey: CGKeyCode = 12
        let flags: CGEventFlags = [.maskCommand, .maskControl]

        guard let down = CGEvent(keyboardEventSource: source, virtualKey: qKey, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: qKey, keyDown: false)
        else { return false }

        down.flags = flags
        up.flags = flags
        down.post(tap: .cgSessionEventTap)
        up.post(tap: .cgSessionEventTap)
        Log.info("screen locked via ⌃⌘Q")
        return true
    }

    /// Turns the display off immediately. Holding system sleep keeps the work
    /// running; there is no reason to also light up the screen.
    static func sleepDisplay() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        task.arguments = ["displaysleepnow"]
        task.standardError = FileHandle.nullDevice
        try? task.run()
    }
}
