import Foundation
import AppKit
import ApplicationServices
import CoreGraphics

/// Focuses the split pane under the gaze, within an already-focused window.
///
/// Two strategies, because editors and terminals differ sharply in how much
/// they expose to Accessibility:
///
///  1. Hit-test the AX tree at the gaze point and focus the element found.
///     Works in Electron editors, Xcode, JetBrains, iTerm2 and Terminal.
///  2. For GPU-rendered terminals that publish almost no AX tree, fall back to
///     the app's own directional pane shortcut, picking a direction from where
///     the gaze sits relative to the window.
@MainActor
final class PaneFocuser {

    /// Apps whose panes are reachable through directional keyboard shortcuts.
    /// `modifiers` are applied to the arrow keys.
    private struct ShortcutProfile {
        let modifiers: CGEventFlags
        /// Some apps need a prefix chord pressed first, e.g. VS Code's Cmd-K.
        let prefix: (key: CGKeyCode, flags: CGEventFlags)?
    }

    private static let shortcutProfiles: [String: ShortcutProfile] = [
        // Terminals with weak AX trees — shortcuts are the only reliable route.
        "net.kovidgoyal.kitty":        .init(modifiers: [.maskShift, .maskAlternate], prefix: nil),
        "com.github.wez.wezterm":      .init(modifiers: [.maskShift, .maskAlternate], prefix: nil),
        "com.mitchellh.ghostty":       .init(modifiers: [.maskCommand, .maskAlternate], prefix: nil),
        "dev.warp.Warp-Stable":        .init(modifiers: [.maskCommand, .maskAlternate], prefix: nil),
        "co.zeit.hyper":               .init(modifiers: [.maskCommand, .maskAlternate], prefix: nil),
        "com.googlecode.iterm2":       .init(modifiers: [.maskCommand, .maskAlternate], prefix: nil),
    ]

    /// Roles worth handing focus to. Anything else is a container or chrome.
    private static let focusableRoles: Set<String> = [
        kAXTextAreaRole, kAXTextFieldRole, "AXWebArea",
        kAXScrollAreaRole, kAXTableRole, kAXOutlineRole, kAXListRole,
    ]

    private var lastPaneFrame: CGRect?

    /// Attempts to focus the pane at `gazePoint` inside `window`.
    /// Returns true when focus was moved.
    @discardableResult
    func focusPane(in window: ScreenWindow, at gazePoint: CGPoint) -> Bool {
        guard Prefs.shared.focusPanes else { return false }
        guard window.frame.contains(gazePoint) else { return false }

        if focusViaAccessibility(pid: window.pid, at: gazePoint) { return true }

        let bundleID = NSRunningApplication(processIdentifier: window.pid)?.bundleIdentifier
        if let bundleID, let profile = Self.shortcutProfiles[bundleID] {
            return focusViaShortcut(profile: profile, window: window, gazePoint: gazePoint)
        }
        return false
    }

    func reset() { lastPaneFrame = nil }

    // MARK: - Accessibility route

    private func focusViaAccessibility(pid: pid_t, at point: CGPoint) -> Bool {
        let app = AXUIElementCreateApplication(pid)

        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(app, Float(point.x), Float(point.y), &hit) == .success,
              let element = hit
        else { return false }

        // Climb to the nearest ancestor that is a sensible focus target.
        var candidate: AXUIElement? = element
        var depth = 0
        while let current = candidate, depth < 12 {
            if let role = Accessibility.string(current, kAXRoleAttribute as String),
               Self.focusableRoles.contains(role) {

                // Suppress redundant work when the gaze has not left the pane.
                if let frame = Accessibility.frame(of: current) {
                    if frame == lastPaneFrame { return false }
                    lastPaneFrame = frame
                }
                return Accessibility.set(current, kAXFocusedAttribute as String, kCFBooleanTrue)
            }
            candidate = Accessibility.attribute(current, kAXParentAttribute as String)
                .map { $0 as! AXUIElement }
            depth += 1
        }
        return false
    }

    // MARK: - Shortcut route

    private enum Direction { case left, right, up, down

        var keyCode: CGKeyCode {
            switch self {
            case .left:  return 123
            case .right: return 124
            case .down:  return 125
            case .up:    return 126
            }
        }
    }

    /// Picks a direction from the gaze's offset within the window. A pane layout
    /// is unknown here, so the dominant axis of the offset is the best guess.
    private func focusViaShortcut(profile: ShortcutProfile,
                                  window: ScreenWindow,
                                  gazePoint: CGPoint) -> Bool {
        let offsetX = (gazePoint.x - window.frame.midX) / window.frame.width
        let offsetY = (gazePoint.y - window.frame.midY) / window.frame.height

        // Near the centre there is no meaningful direction to move in.
        guard max(abs(offsetX), abs(offsetY)) > 0.2 else { return false }

        let direction: Direction = abs(offsetX) >= abs(offsetY)
            ? (offsetX < 0 ? .left : .right)
            : (offsetY < 0 ? .up : .down)

        if let prefix = profile.prefix {
            send(key: prefix.key, flags: prefix.flags)
        }
        send(key: direction.keyCode, flags: profile.modifiers)
        return true
    }

    private func send(key: CGKeyCode, flags: CGEventFlags) {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        // Posting to the session tap delivers to whichever app is frontmost,
        // which by this point is the window we just raised.
        let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cgSessionEventTap)
        up?.post(tap: .cgSessionEventTap)
    }
}
