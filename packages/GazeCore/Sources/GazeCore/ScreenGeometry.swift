import Foundation
import CoreGraphics

/// Screen-layout maths, expressed over plain rectangles so it can be tested
/// against arbitrary display arrangements rather than whatever monitors happen
/// to be plugged in.
public enum ScreenGeometry {

    /// Converts a screen frame from AppKit's bottom-left origin to the
    /// top-left origin that CGWindowList and gaze points use.
    ///
    /// Getting this wrong is silent: everything still runs, focus just lands on
    /// the wrong display whenever a screen sits above or below the primary.
    public static func flipToTopLeft(_ frame: CGRect, primary: CGRect) -> CGRect {
        CGRect(x: frame.origin.x,
               y: primary.maxY - frame.maxY,
               width: frame.width,
               height: frame.height)
    }

    /// The first frame containing the point.
    public static func frame(containing point: CGPoint, in frames: [CGRect]) -> Int? {
        frames.firstIndex { $0.contains(point) }
    }

    /// Nearest frame when the point lands in a gap between displays or past the
    /// outer edge — which happens constantly with imperfect calibration.
    public static func nearestFrame(to point: CGPoint, in frames: [CGRect]) -> Int? {
        guard !frames.isEmpty else { return nil }
        return frames.indices.min { distance(frames[$0], point) < distance(frames[$1], point) }
    }

    /// Zero when the point is inside the rectangle.
    public static func distance(_ rect: CGRect, _ point: CGPoint) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return (dx * dx + dy * dy).squareRoot()
    }

    /// Pulls a point inside the nearest display.
    ///
    /// A linear fit extrapolates without limit, so a head turned further than
    /// anything seen during calibration can predict a coordinate well outside
    /// every screen. Left alone that coordinate is useless for picking a window
    /// or a pane — clamping turns it back into the most plausible real point.
    /// `inset` must clear any edge band the caller applies afterwards. Clamping
    /// flush to the boundary would otherwise land every corrected point inside
    /// the anti-flicker margin, where switching is suppressed — which silently
    /// disables focus switching entirely for anyone whose fit extrapolates.
    public static func clamp(_ point: CGPoint, to frames: [CGRect], inset: CGFloat = 1) -> CGPoint {
        // A point already on a display needs no adjustment.
        if frames.contains(where: { $0.contains(point) }) { return point }
        guard let index = nearestFrame(to: point, in: frames) else { return point }

        let frame = frames[index]
        // Never inset past the middle of a small display.
        let safeX = min(inset, frame.width / 2 - 1)
        let safeY = min(inset, frame.height / 2 - 1)

        return CGPoint(x: min(max(point.x, frame.minX + safeX), frame.maxX - safeX),
                       y: min(max(point.y, frame.minY + safeY), frame.maxY - safeY))
    }

    /// Whether a point sits within `margin` of a frame's left or right edge,
    /// where the choice of display is ambiguous and switching would flicker.
    public static func isNearVerticalEdge(_ point: CGPoint, of rect: CGRect, margin: CGFloat) -> Bool {
        point.x < rect.minX + margin || point.x > rect.maxX - margin
    }
}
