import AppKit
import SwiftUI

/// A click-through dot showing where GazeFocus thinks you are looking.
/// Primarily a diagnostic: if the dot sits consistently off to one side,
/// recalibration is the fix.
@MainActor
final class GazeOverlay {

    private var windows: [NSWindow] = []
    private var dot: NSWindow?

    func setVisible(_ visible: Bool) {
        visible ? show() : hide()
    }

    func update(to point: CGPoint?) {
        guard let dot, let point else { dot?.orderOut(nil); return }
        if !dot.isVisible { dot.orderFrontRegardless() }

        // Convert the top-left global point back to AppKit's bottom-left space.
        guard let primary = NSScreen.screens.first else { return }
        let flipped = CGPoint(x: point.x - 11, y: primary.frame.maxY - point.y - 11)
        dot.setFrameOrigin(flipped)
    }

    private func show() {
        guard dot == nil else { return }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 22, height: 22),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.level = .screenSaver
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.contentView = NSHostingView(rootView: GazeDotView())
        dot = window
    }

    private func hide() {
        dot?.orderOut(nil)
        dot = nil
    }
}

private struct GazeDotView: View {
    var body: some View {
        ZStack {
            Circle().fill(Color.accentColor.opacity(0.25))
            Circle().stroke(Color.accentColor, lineWidth: 1.5)
        }
        .frame(width: 22, height: 22)
    }
}
