import SwiftUI
import ServiceManagement
import PowerCore

struct SettingsView: View {
    @ObservedObject var engine: WakeEngine
    @State private var grace = Prefs.shared.graceSeconds
    @State private var battery = Prefs.shared.batteryThreshold
    @State private var respectLowPower = Prefs.shared.respectLowPower
    @State private var keepScreenOn = Prefs.shared.keepScreenOn
    @State private var honorAssertions = Prefs.shared.honorAppAssertions
    @State private var lidClosed = Prefs.shared.allowLidClosed
    @State private var launchAtLogin = Prefs.shared.launchAtLogin
    @State private var ignored = Prefs.shared.ignoredApps.sorted()
    @State private var lidError: String?
    /// WatchList reads from UserDefaults, which SwiftUI cannot observe; bumping
    /// this is what redraws the toggles after a change.
    @State private var watchListVersion = 0

    var body: some View {
        Form {
            Section("Sleep") {
                VStack(alignment: .leading) {
                    Text("Wait \(formatted(grace)) after work stops")
                    Slider(value: Binding(
                        get: { Double(grace) },
                        set: { grace = Int($0); Prefs.shared.graceSeconds = grace }
                    ), in: 30...600, step: 30)
                    Text("A short pause between build steps won't drop the hold.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Toggle("Keep the screen on too", isOn: $keepScreenOn)
                    .onChange(of: keepScreenOn) { Prefs.shared.keepScreenOn = $1 }
                Text("Off by default — the display sleeps on its own while work continues.")
                    .font(.caption).foregroundStyle(.secondary)

                Toggle("Work with the lid closed", isOn: $lidClosed)
                    .onChange(of: lidClosed) { _, enabled in applyLidSetting(enabled) }
                if let lidError {
                    Text(lidError).font(.caption).foregroundStyle(.red)
                } else {
                    Text("Needs your admin password once. Restored automatically if WakeHold stops.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Battery") {
                VStack(alignment: .leading) {
                    Text("Stop holding below \(battery)%")
                    Slider(value: Binding(
                        get: { Double(battery) },
                        set: { battery = Int($0); Prefs.shared.batteryThreshold = battery }
                    ), in: 0...50, step: 5)
                }
                Toggle("Respect Low Power Mode", isOn: $respectLowPower)
                    .onChange(of: respectLowPower) { Prefs.shared.respectLowPower = $1 }

                LabeledContent("Right now") {
                    Text(engine.powerState.hasBattery
                         ? "\(engine.powerState.percentage)% · \(engine.powerState.onAC ? "plugged in" : "on battery")"
                         : "plugged in")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Detection") {
                Toggle("Trust apps that ask to stay awake", isOn: $honorAssertions)
                    .onChange(of: honorAssertions) { Prefs.shared.honorAppAssertions = $1 }
                Text("Browsers raise this during downloads; editors during exports.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Apps") {
                LabeledContent("Watching") {
                    Text(Prefs.shared.ignoredApps.isEmpty
                         ? "everything"
                         : "all but \(Prefs.shared.ignoredApps.count)")
                        .foregroundStyle(.secondary)
                }
                Text("Choose which apps may keep your Mac awake from the menu bar icon → Choose Apps.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Toggle("Open at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in applyLaunchAtLogin(enabled) }
            }
        }
        .formStyle(.grouped)
        .id(watchListVersion)
        .frame(width: 460, height: 620)
    }

    private func bumpWatchList() {
        watchListVersion += 1
        engine.refresh()
    }

    /// "12 of 12" reads clearly; a partially disabled group stands out.
    private func enabledSummary(for entries: [CatalogEntry]) -> String {
        let on = entries.filter(WatchList.isWatched).count
        return on == entries.count ? "all" : "\(on) of \(entries.count)"
    }

    private func formatted(_ seconds: Int) -> String {
        seconds < 60 ? "\(seconds) seconds"
                     : "\(seconds / 60) minute\(seconds == 60 ? "" : "s")"
    }

    private func applyLidSetting(_ enabled: Bool) {
        let ok = enabled ? ClamshellController.enable() : ClamshellController.disable()
        if ok {
            Prefs.shared.allowLidClosed = enabled
            lidError = nil
        } else {
            // Revert the toggle so it never shows a state the system isn't in.
            lidClosed = !enabled
            lidError = "Administrator approval was declined."
        }
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
