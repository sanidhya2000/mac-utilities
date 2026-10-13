import SwiftUI
import AVFoundation
import GazeCore

/// Four steps: camera, Accessibility, calibration, done.
struct OnboardingView: View {
    @ObservedObject var engine: GazeEngine
    @ObservedObject var calibration: CalibrationController
    let onComplete: () -> Void

    @State private var step = 0
    @State private var cameraGranted = CameraCapture.authorizationStatus() == .authorized
    @State private var axGranted = Accessibility.isTrusted
    @State private var errorMessage: String?
    /// Accessibility trust cannot be observed, so it is polled while visible.
    @State private var poll: Timer?
    /// Seconds spent on the Accessibility step with the grant still unseen.
    @State private var axWaitSeconds = 0

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(28)
            Divider()
            footer
        }
        .frame(width: 520, height: 420)
        .onAppear(perform: startPolling)
        .onDisappear { poll?.invalidate() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "eye")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.tint)
            Text("Set up GazeFocus").font(.headline)
            Spacer()
            Text("Step \(min(step + 1, 4)) of 4")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case 0: permissionStep(
            icon: "camera",
            title: "Allow camera access",
            body: "GazeFocus watches the position of your head to tell which screen you are facing. Video is processed on your Mac, at 15 frames a second, and never leaves it or touches the disk.",
            granted: cameraGranted,
            action: requestCamera,
            actionLabel: "Allow Camera…")

        case 1: accessibilityStep

        case 2: calibrationStep

        default: doneStep
        }
    }

    private func permissionStep(icon: String, title: String, body: String,
                                granted: Bool, action: @escaping () -> Void,
                                actionLabel: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: icon).font(.system(size: 34)).foregroundStyle(.tint)
            Text(title).font(.title3.weight(.semibold))
            Text(body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

            if granted {
                Label("Granted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button(actionLabel, action: action).controlSize(.large)
            }
            Spacer()
        }
    }

    private var accessibilityStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "accessibility").font(.system(size: 34)).foregroundStyle(.tint)
            Text("Allow Accessibility access").font(.title3.weight(.semibold))
            Text("Moving keyboard focus between windows is something only Accessibility permission can do. Open System Settings, switch GazeFocus on in the list, then come back here.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

            if axGranted {
                Label("Granted", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Button("Open System Settings…", action: requestAccessibility)
                    .controlSize(.large)

                // Shown only once waiting has clearly not worked, so it does
                // not distract from the normal path.
                if axWaitSeconds >= 6 {
                    Divider().padding(.vertical, 2)
                    Text("Already switched it on?")
                        .font(.callout.weight(.medium))
                    Text("macOS often won't let an app that is already running notice a new Accessibility grant. Relaunching fixes it.")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Relaunch GazeFocus", action: Relaunch.now)
                }
            }
            Spacer()
        }
    }

    private var calibrationStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "scope").font(.system(size: 34)).foregroundStyle(.tint)
            Text("Calibrate your screens").font(.title3.weight(.semibold))
            Text("A dot will appear at five places on each display. Look at each one and turn your head toward it rather than only moving your eyes. It takes about twenty seconds per screen.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

            if calibration.isRunning {
                ProgressView(value: calibration.progress) {
                    Text("Calibrating \(calibration.currentScreenName)…").font(.caption)
                }
            } else {
                Button("Start Calibration", action: runCalibration).controlSize(.large)
            }

            if let errorMessage {
                Text(errorMessage).font(.callout).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
    }

    private var doneStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 34)).foregroundStyle(.green)
            Text("You're set").font(.title3.weight(.semibold))
            Text("Look at another screen and start typing — focus follows. GazeFocus keeps improving as you work, because every click teaches it a little more about where you were looking.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

            if let error = engine.fitError {
                Label("Average accuracy: about \(Int(error)) points",
                      systemImage: "target")
                    .font(.callout).foregroundStyle(.secondary)
            }

            Text("Pause any time with ⇧⌘G, or from the eye icon in the menu bar.")
                .font(.callout).foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var footer: some View {
        HStack {
            if step > 0 && step < 3 {
                Button("Back") { step -= 1 }
            }
            Spacer()
            Button(step >= 3 ? "Done" : "Continue") {
                if step >= 3 { onComplete() } else { step += 1 }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!canAdvance)
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
    }

    private var canAdvance: Bool {
        switch step {
        case 0:  return cameraGranted
        case 1:  return axGranted
        case 2:  return CalibrationStore.shared.isCalibrated && !calibration.isRunning
        default: return true
        }
    }

    private func requestCamera() {
        CameraCapture.requestAccess { granted in
            cameraGranted = granted
            if !granted {
                errorMessage = "Camera access was denied. Enable it in System Settings › Privacy & Security › Camera."
            }
        }
    }

    private func requestAccessibility() {
        Accessibility.requestTrust()
        Accessibility.openSettingsPane()
    }

    private func runCalibration() {
        errorMessage = nil
        calibration.start { success, message in
            errorMessage = message
            if success {
                engine.recalibrated()
                step = 3
            }
        }
    }

    private func startPolling() {
        poll = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in
                cameraGranted = CameraCapture.authorizationStatus() == .authorized
                axGranted = Accessibility.isTrusted
                if step == 1 && !axGranted { axWaitSeconds += 1 } else { axWaitSeconds = 0 }
            }
        }
    }
}
