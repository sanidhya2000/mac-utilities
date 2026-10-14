import Foundation
import CoreGraphics
import GazeCore

func runGeometryTests(_ h: Harness) {

    h.suite("ScreenGeometry — coordinate flipping") {
        // AppKit puts the origin bottom-left on the primary display; window
        // lists and gaze points use top-left. Getting this wrong is silent:
        // everything runs, focus just lands on the wrong display.
        let primary = CGRect(x: 0, y: 0, width: 2560, height: 1440)

        let flippedPrimary = ScreenGeometry.flipToTopLeft(primary, primary: primary)
        h.close("primary maps to origin", Double(flippedPrimary.minY), 0, 0.001)

        // A laptop screen sitting below the primary, as on this machine.
        let below = CGRect(x: 499, y: -982, width: 1512, height: 982)
        let flippedBelow = ScreenGeometry.flipToTopLeft(below, primary: primary)
        h.close("screen below primary lands beneath it", Double(flippedBelow.minY), 1440, 0.001)
        h.close("x is unchanged by flipping", Double(flippedBelow.minX), 499, 0.001)

        // A display mounted above the primary must map to negative y.
        let above = CGRect(x: 0, y: 1440, width: 2560, height: 1440)
        let flippedAbove = ScreenGeometry.flipToTopLeft(above, primary: primary)
        h.close("screen above primary maps negative", Double(flippedAbove.minY), -1440, 0.001)

        // Flipping is its own inverse.
        let twice = ScreenGeometry.flipToTopLeft(flippedBelow, primary: primary)
        h.close("flip is an involution", Double(twice.minY), Double(below.minY), 0.001)
    }

    h.suite("ScreenGeometry — hit testing") {
        let left = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let right = CGRect(x: 1920, y: 0, width: 1920, height: 1080)
        let frames = [left, right]

        h.equal("point in left screen", ScreenGeometry.frame(containing: CGPoint(x: 100, y: 100), in: frames), 0)
        h.equal("point in right screen", ScreenGeometry.frame(containing: CGPoint(x: 2000, y: 100), in: frames), 1)
        h.check("point outside all screens", ScreenGeometry.frame(containing: CGPoint(x: -500, y: 100), in: frames) == nil)

        // Boundary: the pixel at x=1920 belongs to exactly one screen, never both.
        let boundary = ScreenGeometry.frame(containing: CGPoint(x: 1920, y: 500), in: frames)
        h.check("boundary pixel resolves to one screen", boundary != nil)
    }

    h.suite("ScreenGeometry — nearest frame") {
        let left = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        // A gap, as happens when displays are not flush in the arrangement.
        let right = CGRect(x: 2200, y: 0, width: 1920, height: 1080)
        let frames = [left, right]

        h.equal("point left of everything snaps to left screen",
                ScreenGeometry.nearestFrame(to: CGPoint(x: -800, y: 500), in: frames), 0)
        h.equal("point right of everything snaps to right screen",
                ScreenGeometry.nearestFrame(to: CGPoint(x: 9000, y: 500), in: frames), 1)
        // Imperfect calibration constantly lands points in the gap, which
        // spans 1920...2200 — so the midpoint is 2060.
        h.equal("gap point nearer the left screen picks left",
                ScreenGeometry.nearestFrame(to: CGPoint(x: 2000, y: 500), in: frames), 0)
        h.equal("gap point nearer the right screen picks right",
                ScreenGeometry.nearestFrame(to: CGPoint(x: 2150, y: 500), in: frames), 1)
        h.equal("point just past the left edge of the gap stays left",
                ScreenGeometry.nearestFrame(to: CGPoint(x: 1950, y: 500), in: frames), 0)
        h.check("empty layout returns nil", ScreenGeometry.nearestFrame(to: .zero, in: []) == nil)

        h.close("distance is zero inside the rect",
                Double(ScreenGeometry.distance(left, CGPoint(x: 10, y: 10))), 0, 0.001)
        h.close("distance measures the gap",
                Double(ScreenGeometry.distance(left, CGPoint(x: 1960, y: 500))), 40, 0.001)
    }

    h.suite("ScreenGeometry — clamping") {
        let left = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let right = CGRect(x: 1920, y: 0, width: 1920, height: 1080)
        let frames = [left, right]

        // A point already on a display must be returned untouched.
        let inside = CGPoint(x: 500, y: 500)
        let unchanged = ScreenGeometry.clamp(inside, to: frames)
        h.close("point on a display is unchanged (x)", Double(unchanged.x), 500, 0.001)
        h.close("point on a display is unchanged (y)", Double(unchanged.y), 500, 0.001)

        // Wild extrapolation — the real failure seen in the camera probe.
        let wild = ScreenGeometry.clamp(CGPoint(x: 2952, y: 3199), to: frames)
        h.check("runaway prediction lands on a display",
                frames.contains { $0.contains(wild) },
                "clamped to \(wild)")
        h.check("clamped y is inside the display", wild.y > 0 && wild.y < 1080)

        let farLeft = ScreenGeometry.clamp(CGPoint(x: -9000, y: 500), to: frames)
        h.check("far-left prediction lands on the left display", left.contains(farLeft))

        let farUp = ScreenGeometry.clamp(CGPoint(x: 500, y: -9000), to: frames)
        h.check("far-up prediction lands on a display", left.contains(farUp))

        // The clamped point must clear any edge band applied afterwards,
        // otherwise every corrected prediction is suppressed as "near the edge"
        // and focus switching silently stops working altogether.
        let margin: CGFloat = 40
        let correctedFar = ScreenGeometry.clamp(CGPoint(x: -9000, y: 500), to: frames, inset: margin + 8)
        h.check("clamped point clears the edge band",
                !ScreenGeometry.isNearVerticalEdge(correctedFar, of: left, margin: margin),
                "landed at x=\(correctedFar.x), band ends at \(left.minX + margin)")

        let correctedRight = ScreenGeometry.clamp(CGPoint(x: 99999, y: 500), to: frames, inset: margin + 8)
        h.check("clamped point clears the right edge band",
                !ScreenGeometry.isNearVerticalEdge(correctedRight, of: right, margin: margin))

        // A large inset must not fold past the middle of a narrow display.
        let narrow = [CGRect(x: 0, y: 0, width: 60, height: 60)]
        let folded = ScreenGeometry.clamp(CGPoint(x: -500, y: 30), to: narrow, inset: 400)
        h.check("huge inset stays inside a small display", narrow[0].contains(folded),
                "landed at \(folded)")

        // Degenerate input must not trap.
        let noScreens = ScreenGeometry.clamp(inside, to: [])
        h.close("empty layout returns the input", Double(noScreens.x), 500, 0.001)
    }

    h.suite("ScreenGeometry — edge band") {
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let margin: CGFloat = 40

        // Inside the band the choice of display is ambiguous; suppressing the
        // switch there is what stops focus flickering between two monitors.
        h.check("left edge is in the band", ScreenGeometry.isNearVerticalEdge(CGPoint(x: 10, y: 500), of: screen, margin: margin))
        h.check("right edge is in the band", ScreenGeometry.isNearVerticalEdge(CGPoint(x: 1900, y: 500), of: screen, margin: margin))
        h.check("centre is not in the band", !ScreenGeometry.isNearVerticalEdge(CGPoint(x: 960, y: 500), of: screen, margin: margin))
        h.check("just inside the margin counts", ScreenGeometry.isNearVerticalEdge(CGPoint(x: 39, y: 500), of: screen, margin: margin))
        h.check("just outside the margin does not", !ScreenGeometry.isNearVerticalEdge(CGPoint(x: 41, y: 500), of: screen, margin: margin))
        // A zero margin disables the behaviour rather than matching everything.
        h.check("zero margin matches nothing inside", !ScreenGeometry.isNearVerticalEdge(CGPoint(x: 960, y: 500), of: screen, margin: 0))
    }

    h.suite("ScreenGeometry — realistic layouts") {
        // The arrangement on this machine: 27" primary with a laptop below.
        let primary = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        let laptop = CGRect(x: 499, y: -982, width: 1512, height: 982)
        let frames = [primary, laptop].map { ScreenGeometry.flipToTopLeft($0, primary: primary) }

        h.equal("gaze high up lands on the monitor",
                ScreenGeometry.frame(containing: CGPoint(x: 1280, y: 400), in: frames), 0)
        h.equal("gaze low down lands on the laptop",
                ScreenGeometry.frame(containing: CGPoint(x: 1280, y: 1900), in: frames), 1)

        // A vertical/portrait monitor beside a landscape one.
        let portrait = CGRect(x: 2560, y: 0, width: 1080, height: 1920)
        let mixed = [primary, portrait].map { ScreenGeometry.flipToTopLeft($0, primary: primary) }
        h.check("portrait display is hit-testable",
                ScreenGeometry.frame(containing: CGPoint(x: 3000, y: -200), in: mixed) != nil
                || ScreenGeometry.nearestFrame(to: CGPoint(x: 3000, y: -200), in: mixed) == 1)
    }
}
