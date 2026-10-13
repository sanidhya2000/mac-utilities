import Foundation
import AVFoundation
import AppKit
import Darwin
import GazeCore

/// Reports what the app itself can see, which is the only view that matters:
/// TCC answers depend on the caller's code identity, so a permission can look
/// granted in System Settings while the running build is still refused.
enum Diagnostics {
    @MainActor
    static func run() {
        // stdout is block-buffered when piped; without this, a hang anywhere
        // below would surface as totally silent output rather than a last line.
        setbuf(stdout, nil)
        print("GazeFocus diagnostics\n")

        let bundle = Bundle.main
        print("bundle id:   \(bundle.bundleIdentifier ?? "none")")
        print("bundle path: \(bundle.bundlePath)")

        let camera = CameraCapture.authorizationStatus()
        let cameraText: String
        switch camera {
        case .authorized:    cameraText = "authorized"
        case .denied:        cameraText = "DENIED"
        case .restricted:    cameraText = "restricted"
        case .notDetermined: cameraText = "not yet asked"
        @unknown default:    cameraText = "unknown"
        }
        print("\ncamera:        \(cameraText)")

        // TCC answers depend on the *responsible* process, not just this one.
        // Launched from a terminal, the answer below is the terminal's — which
        // makes this reading actively misleading when the terminal happens to
        // have Accessibility and the app does not.
        let launchedFromTerminal = isLaunchedFromTerminal()
        print("accessibility: \(Accessibility.isTrusted ? "trusted" : "NOT TRUSTED")"
              + (launchedFromTerminal ? "  ← see warning below" : ""))

        print("\ncameras found:")
        fflush(stdout)
        for device in CameraCapture.availableCameras() {
            print("  \(device.localizedName)  [\(device.uniqueID)]")
        }

        print("\nscreens:")
        fflush(stdout)
        for screen in NSScreen.screens {
            let frame = FocusSwitcher.globalFrame(of: screen)
            print("  \(screen.localizedName): \(Int(frame.width))x\(Int(frame.height))"
                  + " at (\(Int(frame.minX)),\(Int(frame.minY)))")
        }

        print("\nreading calibration…")
        let store = CalibrationStore.shared
        print("\ncalibration: \(store.isCalibrated ? "ready" : "not calibrated")")
        print("  samples: \(store.samples.count)")
        if let model = store.model {
            print("  mean error: \(Int(model.meanError)) pt")
        }
        print("  layout now:   \(CalibrationStore.currentLayoutSignature())")

        print("\nguards right now:")
        print("  secure input:    \(SystemGuards.isSecureInputActive)")
        print("  menu open:       \(SystemGuards.isMenuOpen)")
        print("  mission control: \(SystemGuards.isMissionControlActive)")
        print("  launcher front:  \(SystemGuards.activeLauncher ?? "none")")
        print("  blocking reason: \(SystemGuards.blockingReason() ?? "none — safe to switch")")

        if launchedFromTerminal {
            print("""

                WARNING: run from a terminal, so the accessibility line above
                reports your TERMINAL's permission, not GazeFocus's. macOS
                attributes TCC to the responsible parent process.

                For the real answer, open GazeFocus normally and look at the
                menu bar icon, or run:
                    open -a GazeFocus
                A warning triangle there means the app itself is not trusted.
                """)
        }

        if !Accessibility.isTrusted {
            print("""

                Accessibility is not trusted for THIS build.
                Because the app is ad-hoc signed, its identity changes on every
                rebuild, so an entry granted to an earlier build no longer matches.
                Fix: remove GazeFocus from System Settings › Privacy & Security ›
                Accessibility with the − button, then add this exact bundle again.
                """)
        }
    }
}


/// True when the parent is a shell or terminal rather than launchd, meaning
/// TCC answers are inherited from that parent instead of belonging to us.
private func isLaunchedFromTerminal() -> Bool {
    let parent = getppid()
    // launchd is pid 1; anything else started us interactively.
    guard parent != 1 else { return false }

    var name = [CChar](repeating: 0, count: 1024)
    guard proc_pidpath(parent, &name, UInt32(name.count)) > 0 else { return true }
    let path = String(cString: name)
    // A GUI relaunch goes through launchd; a shell, terminal or SSH session
    // does not.
    return !path.hasSuffix("/launchd")
}
