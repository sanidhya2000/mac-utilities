import Foundation
import AVFoundation
import AppKit

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
        print("accessibility: \(Accessibility.isTrusted ? "trusted" : "NOT TRUSTED")")

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
