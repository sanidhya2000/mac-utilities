import SwiftUI
import AVFoundation
import GazeCore

struct SettingsView: View {
    @ObservedObject var engine: GazeEngine
    @ObservedObject var calibration: CalibrationController
    let onRecalibrate: () -> Void

    @State private var settle = Double(Prefs.shared.settleMilliseconds)
    @State private var turn = Prefs.shared.turnThreshold
    @State private var paneDelay = Double(Prefs.shared.paneDelayMilliseconds)
    @State private var typingPause = Prefs.shared.typingPauseSeconds
    @State private var learn = Prefs.shared.learnFromClicks
    @State private var showDot = Prefs.shared.showGazeDot
    @State private var focusPanes = Prefs.shared.focusPanes
    @State private var moveCursor = Prefs.shared.moveCursor
    @State private var respectMouse = Prefs.shared.respectMouse
    @State private var cameraID = Prefs.shared.cameraID ?? ""

    var body: some View {
        Form {
            Section("Switching") {
                slider("Settle before switching", value: $settle, range: 0...1500, step: 50,
                       format: { "\(Int($0)) ms" }) { Prefs.shared.settleMilliseconds = Int($0) }
                Text("How long your gaze must rest before focus follows. Raise it if quick glances steal focus.")
                    .font(.caption).foregroundStyle(.secondary)

                slider("Head turn threshold", value: $turn, range: 0...100, step: 5,
                       format: { "\(Int($0))%" }) { Prefs.shared.turnThreshold = $0 }

                slider("Pane focus delay", value: $paneDelay, range: 0...1500, step: 50,
                       format: { "\(Int($0)) ms" }) { Prefs.shared.paneDelayMilliseconds = Int($0) }

                Toggle("Focus split panes in editors and terminals", isOn: $focusPanes)
                    .onChange(of: focusPanes) { Prefs.shared.focusPanes = $1 }
                Toggle("Move the pointer to the focused screen", isOn: $moveCursor)
                    .onChange(of: moveCursor) { Prefs.shared.moveCursor = $1 }
            }

            Section("Staying out of the way") {
                slider("Pause after typing", value: $typingPause, range: 0...10, step: 0.5,
                       format: { String(format: "%.1f s", $0) }) { Prefs.shared.typingPauseSeconds = $0 }
                Text("Focus never moves mid-keystroke, nor for this long after you stop.")
                    .font(.caption).foregroundStyle(.secondary)

                Toggle("Stand down while the mouse is in use", isOn: $respectMouse)
                    .onChange(of: respectMouse) { Prefs.shared.respectMouse = $1 }
            }

            Section("Accuracy") {
                Toggle("Learn from my clicks", isOn: $learn)
                    .onChange(of: learn) { Prefs.shared.learnFromClicks = $1 }
                Text("Every click is treated as a hint about where you were looking, so accuracy improves as you work.")
                    .font(.caption).foregroundStyle(.secondary)

                if let error = engine.fitError {
                    LabeledContent("Current accuracy") {
                        Text("about \(Int(error)) points off")
                            .foregroundStyle(error < 300 ? Color.secondary : Color.orange)
                    }
                }

                if engine.needsRecalibration {
                    Label("You're sitting at a different distance than when you calibrated. Recalibrating will help.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.callout).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack {
                    Button("Recalibrate…", action: onRecalibrate)
                        .disabled(calibration.isRunning)
                    Button("Reset Learning") {
                        CalibrationStore.shared.clear()
                        engine.recalibrated()
                    }
                }
            }

            Section("Camera") {
                Picker("Camera", selection: $cameraID) {
                    Text("Automatic").tag("")
                    ForEach(CameraCapture.availableCameras(), id: \.uniqueID) { device in
                        Text(device.localizedName).tag(device.uniqueID)
                    }
                }
                .onChange(of: cameraID) { _, value in
                    Prefs.shared.cameraID = value.isEmpty ? nil : value
                    engine.restartCamera()
                }

                Toggle("Show the gaze dot", isOn: $showDot)
                    .onChange(of: showDot) { Prefs.shared.showGazeDot = $1 }
                Text("Draws where GazeFocus thinks you're looking. Useful for checking calibration.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 620)
    }

    private func slider(_ title: String, value: Binding<Double>,
                        range: ClosedRange<Double>, step: Double,
                        format: @escaping (Double) -> String,
                        commit: @escaping (Double) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(format(value.wrappedValue)).foregroundStyle(.secondary).monospacedDigit()
            }
            Slider(value: Binding(get: { value.wrappedValue },
                                  set: { value.wrappedValue = $0; commit($0) }),
                   in: range, step: step)
        }
    }
}
