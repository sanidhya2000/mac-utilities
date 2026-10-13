import Foundation
import AppKit
import ApplicationServices
import CoreGraphics
import GazeCore

/// Moves keyboard focus to a window, and remembers where focus was on each
/// screen so looking back at a display restores what you were last using
/// rather than whatever happens to be frontmost.
@MainActor
final class FocusSwitcher {

    /// Last focused window per screen, keyed by the screen's frame origin.
    private var lastWindowPerScreen: [String: CGWindowID] = [:]

    private(set) var currentScreenKey: String?

    static func key(for screen: NSScreen) -> String {
        "\(Int(screen.frame.origin.x)),\(Int(screen.frame.origin.y))"
    }

    /// Focuses the best window for a gaze point on the given screen.
    /// Returns the window that received focus, if any.
    @discardableResult
    func focus(on screen: NSScreen, gazePoint: CGPoint) -> ScreenWindow? {
        let screenKey = Self.key(for: screen)
        let globalFrame = Self.globalFrame(of: screen)

        // Prefer whatever is directly under the gaze; fall back to the window
        // last used on this screen; finally to whatever is frontmost there.
        let target = WindowFinder.window(at: gazePoint)
            ?? rememberedWindow(for: screenKey, within: globalFrame)
            ?? WindowFinder.frontmostWindow(on: globalFrame)

        guard let target else { return nil }
        guard raise(target) else { return nil }

        lastWindowPerScreen[screenKey] = target.windowID
        currentScreenKey = screenKey

        if Prefs.shared.moveCursor {
            moveCursor(into: target, gazePoint: gazePoint, screenFrame: globalFrame)
        }
        return target
    }

    /// Records focus that the user established themselves, so a manual click is
    /// not forgotten the moment they glance away and back.
    func noteManualFocus(_ window: ScreenWindow) {
        guard let screen = Self.screen(containing: window.frame) else { return }
        let screenKey = Self.key(for: screen)
        lastWindowPerScreen[screenKey] = window.windowID
        currentScreenKey = screenKey
    }

    private func rememberedWindow(for screenKey: String, within frame: CGRect) -> ScreenWindow? {
        guard let windowID = lastWindowPerScreen[screenKey] else { return nil }
        // The window may have been closed or moved to another display.
        return WindowFinder.windowsFrontToBack().first {
            $0.windowID == windowID && frame.intersects($0.frame)
        }
    }

    /// Raising means activating the owning app *and* raising the specific
    /// window — activation alone lands on whichever window that app had front.
    private func raise(_ window: ScreenWindow) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: window.pid) else { return false }

        if let axWindow = WindowFinder.axWindow(for: window) {
            Accessibility.perform(axWindow, kAXRaiseAction as String)
            Accessibility.set(axWindow, kAXMainAttribute as String, kCFBooleanTrue)
            Accessibility.set(axWindow, kAXFocusedAttribute as String, kCFBooleanTrue)
        }

        return app.activate(options: [])
    }

    /// Carries the pointer along so hover states and scroll wheel follow the
    /// eyes too. The cursor is placed at the gaze point when that lands inside
    /// the window, otherwise at the window's centre.
    private func moveCursor(into window: ScreenWindow, gazePoint: CGPoint, screenFrame: CGRect) {
        let destination = window.frame.contains(gazePoint)
            ? gazePoint
            : CGPoint(x: window.frame.midX, y: window.frame.midY)
        CGWarpMouseCursorPosition(destination)
        // Without this the pointer visually jumps but the system keeps
        // associating mouse deltas with the old location.
        CGAssociateMouseAndMouseCursorPosition(1)
    }

    // MARK: - Coordinate helpers

    /// NSScreen uses a bottom-left origin on the primary display; CGWindowList
    /// and gaze points use top-left. This converts a screen to the top-left
    /// space everything else in this app works in.
    static func globalFrame(of screen: NSScreen) -> CGRect {
        guard let primary = NSScreen.screens.first else { return screen.frame }
        return ScreenGeometry.flipToTopLeft(screen.frame, primary: primary.frame)
    }

    static func screen(containing frame: CGRect) -> NSScreen? {
        NSScreen.screens.max { a, b in
            globalFrame(of: a).intersection(frame).area < globalFrame(of: b).intersection(frame).area
        }
    }

    /// The screen a gaze point falls on, in top-left global coordinates.
    static func screen(at point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { globalFrame(of: $0).contains(point) }
    }

    /// Nearest screen when the point lands in a gap or past the outer edge,
    /// which happens constantly with imperfect calibration.
    static func nearestScreen(to point: CGPoint) -> NSScreen? {
        let screens = NSScreen.screens
        let frames = screens.map(globalFrame(of:))
        guard let index = ScreenGeometry.nearestFrame(to: point, in: frames) else { return nil }
        return screens[index]
    }
}

extension CGRect {
    var area: CGFloat { width * height }
}
