import Foundation
import AppKit
import Carbon.HIToolbox
import CoreGraphics

/// Moments when moving focus would break something, detected from system state
/// rather than from the user's input.
///
/// Each of these was reasoned out from the same failure the copy/paste race
/// showed: focus switching is only safe when the user is between actions, and
/// several system states mean they are visibly mid-action.
@MainActor
enum SystemGuards {

    /// Apps whose windows are transient command surfaces. Raising anything else
    /// dismisses them, losing whatever the user had typed.
    private static let launcherBundleIDs: Set<String> = [
        "com.apple.Spotlight",
        "com.raycast.macos",
        "com.runningwithcrayons.Alfred",
        "at.obdev.LaunchBar",
        "com.apple.finder.Open",          // open/save panels run out of process
        "com.googlecode.iterm2.quickopen",
    ]

    /// The reason focus must not move right now, or nil when it is safe.
    static func blockingReason() -> String? {
        if isSecureInputActive  { return "secure input" }
        if isMenuOpen           { return "menu open" }
        if isMissionControlActive { return "Mission Control" }
        if let launcher = activeLauncher { return launcher }
        return nil
    }

    /// Secure Event Input is the dangerous one.
    ///
    /// While a password field is focused, macOS stops delivering key events to
    /// global monitors. The typing guard therefore goes quiet exactly when the
    /// user is typing something they must not misdirect — so without this check
    /// GazeFocus could move focus mid-password and send the rest of it to
    /// another window.
    static var isSecureInputActive: Bool {
        IsSecureEventInputEnabled()
    }

    /// An open menu is tracking the mouse and swallows events; raising a window
    /// closes it under the user's hand.
    static var isMenuOpen: Bool {
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return false }

        let menuLayer = Int(CGWindowLevelForKey(.popUpMenuWindow))
        return windows.contains { info in
            (info[kCGWindowLayer as String] as? Int ?? 0) >= menuLayer
        }
    }

    /// Mission Control and App Exposé are drawn by the Dock across the whole
    /// screen; focus changes underneath them are both invisible and disruptive.
    static var isMissionControlActive: Bool {
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return false }

        let screenArea = NSScreen.screens.reduce(0.0) { $0 + $1.frame.width * $1.frame.height }
        for info in windows {
            guard info[kCGWindowOwnerName as String] as? String == "Dock" else { continue }
            guard let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                  let frame = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
            else { continue }
            // The Dock itself is a thin strip; an Exposé backdrop is enormous.
            if frame.width * frame.height > screenArea * 0.4 { return true }
        }
        return false
    }

    /// Spotlight, Raycast and friends — raising another window loses the query.
    static var activeLauncher: String? {
        guard let front = NSWorkspace.shared.frontmostApplication,
              let bundleID = front.bundleIdentifier,
              launcherBundleIDs.contains(bundleID)
        else { return nil }
        return front.localizedName ?? "launcher"
    }

    /// Whether a window belongs to a Space other than the one on screen.
    ///
    /// `CGWindowListCopyWindowInfo` with `.optionOnScreenOnly` already reports
    /// only the current Space, so focus can never be pulled to a window the
    /// user cannot see. Kept explicit because it is easy to break by relaxing
    /// that option later.
    static let onlyCurrentSpaceIsVisible = true
}
