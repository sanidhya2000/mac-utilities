import Foundation
import CoreGraphics
import AppKit

/// Renders both app icons at every size macOS asks for.
///
/// Drawn in code rather than exported from a design tool so the icons stay
/// reproducible and can be re-tuned without binary assets in the repo.

let sizes = [16, 32, 64, 128, 256, 512, 1024]

// macOS icons sit inside the canvas rather than filling it; ~0.82 matches the
// proportion Apple's own icons use, so these line up in the Dock.
let squircleScale: CGFloat = 0.82

struct Palette {
    let backgroundTop: CGColor
    let backgroundBottom: CGColor
    let accent: CGColor
    let accentDim: CGColor
    let ink: CGColor
}

func rgb(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat(r)/255, green: CGFloat(g)/255, blue: CGFloat(b)/255, alpha: a)
}

/// Both icons share a dark terminal-panel base so they read as a pair of
/// developer tools sitting next to each other in the Dock.
let gazePalette = Palette(
    backgroundTop:    rgb(42, 52, 72),
    backgroundBottom: rgb(20, 25, 37),
    accent:           rgb(96, 165, 250),
    accentDim:        rgb(96, 165, 250, 0.32),
    ink:              rgb(236, 243, 255)
)

/// Emerald, so the three sit apart at a glance in the Dock: blue for focus,
/// amber for awake, green for locked-and-running.
let afkPalette = Palette(
    backgroundTop:    rgb(34, 58, 50),
    backgroundBottom: rgb(16, 28, 24),
    accent:           rgb(52, 211, 153),
    accentDim:        rgb(52, 211, 153, 0.30),
    ink:              rgb(233, 255, 246)
)

let wakePalette = Palette(
    backgroundTop:    rgb(62, 50, 36),
    backgroundBottom: rgb(26, 21, 16),
    accent:           rgb(251, 191, 36),
    accentDim:        rgb(251, 191, 36, 0.30),
    ink:              rgb(255, 246, 229)
)

func context(size: Int) -> CGContext {
    let ctx = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high
    return ctx
}

/// The rounded-rect body, with a vertical gradient and a hairline top edge.
func drawBody(_ ctx: CGContext, _ s: CGFloat, _ p: Palette) -> CGRect {
    let side = s * squircleScale
    let origin = (s - side) / 2
    let rect = CGRect(x: origin, y: origin, width: side, height: side)
    let radius = side * 0.225

    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                              colors: [p.backgroundTop, p.backgroundBottom] as CFArray,
                              locations: [0, 1])!
    ctx.drawLinearGradient(gradient,
                           start: CGPoint(x: rect.midX, y: rect.maxY),
                           end: CGPoint(x: rect.midX, y: rect.minY),
                           options: [])
    ctx.restoreGState()

    // A faint inner highlight along the top keeps it from looking flat.
    ctx.saveGState()
    ctx.addPath(path)
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.10))
    ctx.setLineWidth(max(1, s * 0.006))
    ctx.strokePath()
    ctx.restoreGState()

    return rect
}

/// GazeFocus: a focus reticle framing a terminal cursor.
func drawGaze(_ ctx: CGContext, _ s: CGFloat) {
    let p = gazePalette
    let body = drawBody(ctx, s, p)

    let unit = body.width
    let bracket = unit * 0.21          // arm length of each corner bracket
    let inset = unit * 0.17
    let line = unit * 0.064

    ctx.setStrokeColor(p.accent)
    ctx.setLineWidth(line)
    ctx.setLineCap(.round)

    // Four corner brackets — the universal "focus here" mark.
    let corners: [(CGPoint, CGPoint, CGPoint)] = [
        // (corner, armEndX, armEndY)
        (CGPoint(x: body.minX + inset, y: body.maxY - inset),
         CGPoint(x: body.minX + inset + bracket, y: body.maxY - inset),
         CGPoint(x: body.minX + inset, y: body.maxY - inset - bracket)),

        (CGPoint(x: body.maxX - inset, y: body.maxY - inset),
         CGPoint(x: body.maxX - inset - bracket, y: body.maxY - inset),
         CGPoint(x: body.maxX - inset, y: body.maxY - inset - bracket)),

        (CGPoint(x: body.minX + inset, y: body.minY + inset),
         CGPoint(x: body.minX + inset + bracket, y: body.minY + inset),
         CGPoint(x: body.minX + inset, y: body.minY + inset + bracket)),

        (CGPoint(x: body.maxX - inset, y: body.minY + inset),
         CGPoint(x: body.maxX - inset - bracket, y: body.minY + inset),
         CGPoint(x: body.maxX - inset, y: body.minY + inset + bracket)),
    ]
    for (corner, armX, armY) in corners {
        ctx.move(to: armX); ctx.addLine(to: corner); ctx.addLine(to: armY)
    }
    ctx.strokePath()

    // The caret block: a monospace cursor, the thing focus actually moves.
    let caretW = unit * 0.135
    let caretH = unit * 0.36
    let caret = CGRect(x: body.midX - caretW / 2, y: body.midY - caretH / 2,
                       width: caretW, height: caretH)
    ctx.setFillColor(p.ink)
    ctx.fill(caret)

    // Underline beneath it, as a text baseline.
    let baseW = unit * 0.30
    ctx.setFillColor(p.accentDim)
    ctx.fill(CGRect(x: body.midX - baseW / 2, y: caret.minY - unit * 0.10,
                    width: baseW, height: line * 0.72))
}

/// WakeHold: a cup, drawn geometrically, with steam.
func drawWake(_ ctx: CGContext, _ s: CGFloat) {
    let p = wakePalette
    let body = drawBody(ctx, s, p)

    let unit = body.width
    let line = unit * 0.058
    ctx.setLineWidth(line)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)

    let cupTopW = unit * 0.40
    let cupBotW = unit * 0.32
    let cupH = unit * 0.30
    let cupTopY = body.midY - unit * 0.015
    let cupBotY = cupTopY - cupH
    // Shifted left so the handle has room without the whole mark drifting.
    let cx = body.midX - unit * 0.055

    // Handle first, so the cup wall overlaps where the two meet.
    let handleCenter = CGPoint(x: cx + cupTopW / 2, y: cupTopY - cupH * 0.42)
    let handleRadius = unit * 0.115
    ctx.setStrokeColor(p.accent)
    ctx.setLineWidth(line * 0.85)
    ctx.addArc(center: handleCenter, radius: handleRadius,
               startAngle: -.pi / 2.1, endAngle: .pi / 2.1, clockwise: false)
    ctx.strokePath()

    // Cup body: straight tapered walls into a softly rounded base.
    ctx.setLineWidth(line)
    let cup = CGMutablePath()
    cup.move(to: CGPoint(x: cx - cupTopW / 2, y: cupTopY))
    cup.addLine(to: CGPoint(x: cx - cupBotW / 2, y: cupBotY + unit * 0.035))
    cup.addQuadCurve(to: CGPoint(x: cx - cupBotW / 2 + unit * 0.045, y: cupBotY),
                     control: CGPoint(x: cx - cupBotW / 2, y: cupBotY))
    cup.addLine(to: CGPoint(x: cx + cupBotW / 2 - unit * 0.045, y: cupBotY))
    cup.addQuadCurve(to: CGPoint(x: cx + cupBotW / 2, y: cupBotY + unit * 0.035),
                     control: CGPoint(x: cx + cupBotW / 2, y: cupBotY))
    cup.addLine(to: CGPoint(x: cx + cupTopW / 2, y: cupTopY))
    ctx.addPath(cup)
    ctx.strokePath()

    // Rim across the top, so the cup reads as open rather than as a bucket.
    ctx.move(to: CGPoint(x: cx - cupTopW / 2, y: cupTopY))
    ctx.addLine(to: CGPoint(x: cx + cupTopW / 2, y: cupTopY))
    ctx.strokePath()

    // Saucer: a thin understroke, not a slab.
    ctx.setStrokeColor(p.accentDim)
    ctx.setLineWidth(line * 0.62)
    ctx.move(to: CGPoint(x: cx - cupTopW * 0.70, y: cupBotY - unit * 0.072))
    ctx.addLine(to: CGPoint(x: cx + cupTopW * 0.70, y: cupBotY - unit * 0.072))
    ctx.strokePath()

    // Steam: two offset S-curves, taller than they are wide so they read as
    // rising rather than as punctuation.
    ctx.setStrokeColor(p.ink)
    ctx.setLineWidth(line * 0.62)
    for (index, offset) in [-unit * 0.088, unit * 0.088].enumerated() {
        let x = cx + offset
        let baseY = cupTopY + unit * 0.055
        let height = unit * (index == 0 ? 0.20 : 0.165)
        let sway = unit * 0.052

        let steam = CGMutablePath()
        steam.move(to: CGPoint(x: x, y: baseY))
        steam.addCurve(
            to: CGPoint(x: x, y: baseY + height),
            control1: CGPoint(x: x + sway, y: baseY + height * 0.33),
            control2: CGPoint(x: x - sway, y: baseY + height * 0.67))
        ctx.addPath(steam)
        ctx.strokePath()
    }
}

/// AFK: a padlock with a shell prompt inside it — locked, still executing.
func drawAFK(_ ctx: CGContext, _ s: CGFloat) {
    let p = afkPalette
    let body = drawBody(ctx, s, p)

    let unit = body.width
    let line = unit * 0.065
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)

    // Padlock body.
    let lockW = unit * 0.46
    let lockH = unit * 0.345
    let lockRect = CGRect(x: body.midX - lockW / 2,
                          y: body.midY - lockH * 0.80,
                          width: lockW, height: lockH)
    let lockPath = CGPath(roundedRect: lockRect,
                          cornerWidth: unit * 0.055, cornerHeight: unit * 0.055,
                          transform: nil)
    ctx.setStrokeColor(p.accent)
    ctx.setLineWidth(line)
    ctx.addPath(lockPath)
    ctx.strokePath()

    // Shackle: a half-arc whose ends land exactly on the body's top edge, so
    // there are no leg stubs poking through the outline.
    let shackleRadius = unit * 0.145
    ctx.setLineWidth(line * 0.92)
    ctx.addArc(center: CGPoint(x: body.midX, y: lockRect.maxY),
               radius: shackleRadius,
               startAngle: 0, endAngle: .pi, clockwise: false)
    ctx.strokePath()

    // Inside the lock: a prompt chevron and caret — work still running.
    ctx.setStrokeColor(p.ink)
    ctx.setLineWidth(line * 0.72)
    let chevron = unit * 0.052
    let cxp = body.midX - unit * 0.072
    let cyp = lockRect.midY + unit * 0.012
    ctx.move(to: CGPoint(x: cxp - chevron, y: cyp + chevron))
    ctx.addLine(to: CGPoint(x: cxp + chevron * 0.55, y: cyp))
    ctx.addLine(to: CGPoint(x: cxp - chevron, y: cyp - chevron))
    ctx.strokePath()

    // Caret block beside the prompt.
    ctx.setFillColor(p.ink)
    ctx.fill(CGRect(x: cxp + chevron * 1.5, y: cyp - chevron * 1.05,
                    width: unit * 0.047, height: chevron * 2.1))
}

func render(name: String, draw: (CGContext, CGFloat) -> Void, into directory: URL) throws {
    let iconset = directory.appendingPathComponent("\(name).iconset")
    try? FileManager.default.removeItem(at: iconset)
    try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

    // .iconset expects each logical size at both 1x and 2x.
    let pairs: [(logical: Int, scale: Int)] = [
        (16,1),(16,2),(32,1),(32,2),(128,1),(128,2),(256,1),(256,2),(512,1),(512,2)
    ]

    for (logical, scale) in pairs {
        let pixels = logical * scale
        let ctx = context(size: pixels)
        draw(ctx, CGFloat(pixels))
        guard let image = ctx.makeImage() else { continue }

        let suffix = scale == 1 ? "" : "@2x"
        let url = iconset.appendingPathComponent("icon_\(logical)x\(logical)\(suffix).png")
        let rep = NSBitmapImageRep(cgImage: image)
        rep.size = NSSize(width: pixels, height: pixels)
        guard let data = rep.representation(using: .png, properties: [:]) else { continue }
        try data.write(to: url)
    }
    print("rendered \(iconset.lastPathComponent) (\(pairs.count) files)")
}

let output = URL(fileURLWithPath: CommandLine.arguments.count > 1
                 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath)

try render(name: "GazeFocus", draw: drawGaze, into: output)
try render(name: "WakeHold",  draw: drawWake, into: output)
try render(name: "AFK",       draw: drawAFK,  into: output)
