import Foundation
import AppKit
import CoreGraphics

/// Watches the keyboard and pointer so focus never moves at a moment that
/// would disrupt the user.
///
/// This is the difference between a usable tool and an infuriating one: moving
/// focus mid-keystroke sends the rest of a sentence to the wrong window, and
/// overriding a deliberate click is worse than doing nothing at all.
@MainActor
final class InputGuards {

    /// Text-producing keystrokes only. Command chords are tracked separately
    /// because they mean something completely different for focus.
    private var lastTextKeystroke = Date.distantPast
    /// Last ⌘-chord, and whether it was a copy or cut.
    private var lastCommandChord = Date.distantPast
    private var lastCopy = Date.distantPast
    /// Modifiers physically held right now.
    private var heldModifiers: NSEvent.ModifierFlags = []
    private var lastPointerMove = Date.distantPast
    private var lastPointerPosition = CGPoint.zero
    private var monitors: [Any] = []

    /// Called when the user clicks, so the engine can learn from it.
    var onClick: ((CGPoint) -> Void)?

    func start() {
        // Global monitors observe other apps' events; they require the same
        // Accessibility trust the focus switching already needs.
        let keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            let flags = event.modifierFlags
            let isCommand = flags.contains(.command)
            let isControl = flags.contains(.control)
            // keyCode 8 is C, 7 is X — the two that precede a paste elsewhere.
            let isCopyOrCut = isCommand && (event.keyCode == 8 || event.keyCode == 7)

            Task { @MainActor in
                guard let self else { return }
                if isCommand || isControl {
                    self.lastCommandChord = Date()
                    if isCopyOrCut { self.lastCopy = Date() }
                } else {
                    self.lastTextKeystroke = Date()
                }
            }
        }

        // Tracks modifiers being held so focus never moves mid-shortcut.
        let flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            let flags = event.modifierFlags
            Task { @MainActor in self?.heldModifiers = flags }
        }

        let mouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .scrollWheel]
        ) { [weak self] _ in
            Task { @MainActor in self?.notePointerActivity() }
        }

        let clickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in
                self?.notePointerActivity()
                self?.onClick?(Self.pointerLocation())
            }
        }

        monitors = [keyMonitor, flagsMonitor, mouseMonitor, clickMonitor].compactMap { $0 }
    }

    func stop() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
    }

    /// Ignores the synthetic move the app itself makes when warping the cursor.
    private func notePointerActivity() {
        let position = Self.pointerLocation()
        defer { lastPointerPosition = position }
        guard hypot(position.x - lastPointerPosition.x,
                    position.y - lastPointerPosition.y) > 2 else { return }
        lastPointerMove = Date()
    }

    /// Suppress switching while typing, and for a configurable tail afterwards.
    ///
    /// Deliberately counts only text keystrokes. A ⌘-chord is a command, not
    /// typing: after ⌘C the user very often looks at another screen to paste,
    /// and blocking the switch for the full typing pause would send that ⌘V to
    /// the window they just left — the exact mistake this app exists to stop.
    var isTyping: Bool {
        Date().timeIntervalSince(lastTextKeystroke) < Prefs.shared.typingPauseSeconds
    }

    /// True while a modifier is physically down. Switching focus mid-chord
    /// would deliver the second half of the shortcut to a different app.
    var isHoldingModifier: Bool {
        !heldModifiers.intersection([.command, .control, .option]).isEmpty
    }

    /// A copy or cut happened recently, so a paste into another window is
    /// likely imminent and focus should follow the eyes more eagerly.
    var expectsPaste: Bool {
        Date().timeIntervalSince(lastCopy) < 8
    }

    /// A hand on the trackpad means the user is driving focus themselves.
    var isUsingPointer: Bool {
        guard Prefs.shared.respectMouse else { return false }
        return Date().timeIntervalSince(lastPointerMove) < 1.5
    }

    /// Reports the cursor in top-left global coordinates to match gaze points.
    static func pointerLocation() -> CGPoint {
        let location = NSEvent.mouseLocation
        guard let primary = NSScreen.screens.first else { return location }
        return CGPoint(x: location.x, y: primary.frame.maxY - location.y)
    }

    func noteOwnCursorWarp() {
        lastPointerPosition = Self.pointerLocation()
    }
}
