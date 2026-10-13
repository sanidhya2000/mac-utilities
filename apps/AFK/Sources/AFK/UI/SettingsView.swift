import SwiftUI
import ServiceManagement
import PowerCore

struct SettingsView: View {
    @ObservedObject var session: AwaySession

    @State private var mode = Prefs.shared.releaseMode
    @State private var timerMinutes = Double(Prefs.shared.timerMinutes)
    @State private var maxHours = Double(Prefs.shared.maxHours)
    @State private var batteryFloor = Double(Prefs.shared.batteryFloor)
    @State private var respectLowPower = Prefs.shared.respectLowPower
    @State private var lockOnArm = Prefs.shared.lockOnArm
    @State private var sleepDisplay = Prefs.shared.sleepDisplayOnArm
    @State private var lidClosed = Prefs.shared.allowLidClosed
    @State private var grace = Double(Prefs.shared.graceSeconds)
    @State private var launchAtLogin = Prefs.shared.launchAtLogin
    @State private var lidError: String?

    var body: some View {
        Form {
            Section("When you go AFK") {
                Picker("Stay awake", selection: $mode) {
                    ForEach(ReleaseMode.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .onChange(of: mode) { Prefs.shared.releaseMode = $1 }

                if mode == .timer {
                    stepperRow("For", value: $timerMinutes, range: 5...480, step: 5,
                               format: { "\(Int($0)) min" }) { Prefs.shared.timerMinutes = Int($0) }
                }

                if mode == .whenWorkFinishes {
                    stepperRow("Wait after work stops", value: $grace, range: 30...600, step: 30,
                               format: { $0 < 60 ? "\(Int($0))s" : "\(Int($0) / 60) min" }) {
                        Prefs.shared.graceSeconds = Int($0)
                    }
                    Text("Then the Mac is allowed to sleep on its own.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Toggle("Lock the screen", isOn: $lockOnArm)
                    .onChange(of: lockOnArm) { Prefs.shared.lockOnArm = $1 }
                Toggle("Turn the display off", isOn: $sleepDisplay)
                    .onChange(of: sleepDisplay) { Prefs.shared.sleepDisplayOnArm = $1 }
                    .disabled(!lockOnArm)

                if !ScreenLock.usesSystemLock {
                    Label("This Mac needs the ⌃⌘Q shortcut to lock. If you've remapped it, locking won't work.",
                          systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section("Safety") {
                stepperRow("Never hold longer than", value: $maxHours, range: 1...24, step: 1,
                           format: { "\(Int($0)) h" }) { Prefs.shared.maxHours = Int($0) }
                Text("A forgotten session always ends on its own.")
                    .font(.caption).foregroundStyle(.secondary)

                stepperRow("Stop below", value: $batteryFloor, range: 0...50, step: 5,
                           format: { "\(Int($0))%" }) { Prefs.shared.batteryFloor = Int($0) }

                Toggle("Respect Low Power Mode", isOn: $respectLowPower)
                    .onChange(of: respectLowPower) { Prefs.shared.respectLowPower = $1 }

                LabeledContent("Right now") {
                    Text(session.powerState.hasBattery
                         ? "\(session.powerState.percentage)% · \(session.powerState.onAC ? "plugged in" : "on battery")"
                         : "plugged in")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Lid") {
                Toggle("Keep working with the lid closed", isOn: $lidClosed)
                    .onChange(of: lidClosed) { _, enabled in applyLid(enabled) }
                if let lidError {
                    Text(lidError).font(.caption).foregroundStyle(.red)
                } else {
                    Text("Needs your admin password once. Restored automatically when the session ends.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            if let report = session.lastReport {
                Section("Last session") {
                    LabeledContent("Ended") { Text(report.endReason.rawValue).foregroundStyle(.secondary) }
                    LabeledContent("Lasted") {
                        Text("\(Int(report.duration / 60)) min").foregroundStyle(.secondary)
                    }
                    if !report.appsSeen.isEmpty {
                        LabeledContent("Working") {
                            Text(report.appsSeen.prefix(4).joined(separator: ", "))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
            }

            Section {
                Toggle("Open at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in applyLaunchAtLogin(enabled) }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 560)
    }

    private func stepperRow(_ title: String, value: Binding<Double>,
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

    private func applyLid(_ enabled: Bool) {
        // Only ask for the password when turning it on; the session itself
        // applies and reverts the flag around each run.
        if enabled {
            guard ClamshellController.enable() else {
                lidClosed = false
                lidError = "Administrator approval was declined."
                return
            }
            ClamshellController.disable()
        }
        Prefs.shared.allowLidClosed = enabled
        lidError = nil
    }

    private func applyLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            Prefs.shared.launchAtLogin = enabled
        } catch {
            launchAtLogin = !enabled
            Log.error("launch at login failed: \(error.localizedDescription)")
        }
    }
}
