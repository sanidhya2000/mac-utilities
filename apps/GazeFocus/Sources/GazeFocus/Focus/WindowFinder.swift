import Foundation
import AppKit
import ApplicationServices
import CoreGraphics

/// A window on screen, as seen through the window-server list.
struct ScreenWindow {
    let pid: pid_t
    let windowID: CGWindowID
    let frame: CGRect
    let ownerName: String
    let title: String
    /// Smaller is nearer the front.
    let layerIndex: Int
}

/// Finds which window sits under a point.
///
/// The window-server list is used for geometry because it already reports
/// front-to-back order and covers every app, whereas walking AX trees for all
/// running apps is slow and misses windows an app declines to expose.
enum WindowFinder {

    /// Global-coordinate frames use a top-left origin with y growing downward,
    /// which matches CGWindowList but not NSScreen.
    static func windowsFrontToBack() -> [ScreenWindow] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        var result: [ScreenWindow] = []
        for (index, info) in raw.enumerated() {
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  let windowID = info[kCGWindowNumber as String] as? CGWindowID,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                  let frame = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
            else { continue }

            // Layer 0 is normal app windows; menu bars and overlays sit above.
            let layer = info[kCGWindowLayer as String] as? Int ?? 0
            guard layer == 0 else { continue }

            // Ignore slivers: shadows and helper windows are not focus targets.
            guard frame.width > 80, frame.height > 60 else { continue }

            result.append(ScreenWindow(
                pid: pid,
                windowID: windowID,
                frame: frame,
                ownerName: info[kCGWindowOwnerName as String] as? String ?? "",
                title: info[kCGWindowName as String] as? String ?? "",
                layerIndex: index
            ))
        }
        return result
    }

    /// Frontmost window containing the point, in global top-left coordinates.
    static func window(at point: CGPoint) -> ScreenWindow? {
        windowsFrontToBack().first { $0.frame.contains(point) }
    }

    /// Frontmost window on a given screen, used when the gaze lands on empty
    /// desktop and the last-used window for that screen is gone.
    static func frontmostWindow(on screenFrame: CGRect) -> ScreenWindow? {
        windowsFrontToBack().first { screenFrame.intersects($0.frame) }
    }

    /// Matches a window-server window to its AX counterpart by frame, which is
    /// the only reliable join between the two APIs.
    static func axWindow(for window: ScreenWindow) -> AXUIElement? {
        let app = AXUIElementCreateApplication(window.pid)
        guard let windows = Accessibility.attribute(app, kAXWindowsAttribute as String)
                as? [AXUIElement] else { return nil }

        var best: AXUIElement?
        var bestDistance = Double.greatestFiniteMagnitude

        for candidate in windows {
            guard let frame = Accessibility.frame(of: candidate) else { continue }
            let distance = hypot(frame.origin.x - window.frame.origin.x,
                                 frame.origin.y - window.frame.origin.y)
                + abs(frame.width - window.frame.width)
                + abs(frame.height - window.frame.height)
            if distance < bestDistance {
                bestDistance = distance
                best = candidate
            }
        }
        // Tolerate rounding between the two APIs, reject a genuine mismatch.
        return bestDistance < 12 ? best : nil
    }
}
