import AppKit
import SwiftUI
import Combine
import PowerCore

/// The keyboard glyph and its menu. One click arms a session.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let session: AwaySession
    private var cancellables: Set<AnyCancellable> = []
    private var settingsWindow: NSWindow?
    private var clock: Timer?

    init(session: AwaySession) {
        self.session = session
        super.init()

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        session.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.render($0) }
            .store(in: &cancellables)

        // Surface what happened while the user was away, once they're back.
        session.$pendingReport
            .compactMap { $0 }
            .receive(on: RunLoop.main)
            .sink { [weak self] report in self?.present(report) }
            .store(in: &cancellables)

        // The title counts up while armed, so the state is readable at a glance.
        clock = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.render(self?.session.state ?? .idle) }
        }
    }

    private func render(_ state: SessionState) {
        guard let button = statusItem.button else { return }

        switch state {
        case .idle:
            button.image = NSImage(systemSymbolName: "moon.zzz",
                                   accessibilityDescription: "AFK idle")
            button.title = ""
            button.toolTip = "AFK — not armed"

        case .armed(let since):
            button.image = NSImage(systemSymbolName: "lock.laptopcomputer",
                                   accessibilityDescription: "AFK armed")
            button.title = " " + Self.elapsed(since: since)
            button.toolTip = "AFK — locked and holding sleep"

        case .winding(let secondsLeft):
            button.image = NSImage(systemSymbolName: "lock.laptopcomputer",
                                   accessibilityDescription: "AFK finishing")
            button.title = " \(secondsLeft)s"
            button.toolTip = "Work finished — releasing in \(secondsLeft)s"
        }
        button.image?.isTemplate = true
    }

    private static func elapsed(since: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(since))
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        return hours > 0 ? "\(hours)h\(minutes)m" : "\(minutes)m"
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        switch session.state {
        case .idle:
            let header = NSMenuItem(
                title: "Ready — \(Prefs.shared.releaseMode.label.lowercased())",
                action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            menu.addItem(.separator())

            let arm = NSMenuItem(title: "Go AFK", action: #selector(arm), keyEquivalent: "l")
            arm.keyEquivalentModifierMask = [.command, .shift]
            arm.target = self
            menu.addItem(arm)

            menu.addItem(.separator())
            addModePicker(to: menu)

        case .armed(let since):
            let header = NSMenuItem(title: "Away for \(Self.elapsed(since: since))",
                                    action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)

            let mode = NSMenuItem(title: Prefs.shared.releaseMode.label,
                                  action: nil, keyEquivalent: "")
            mode.isEnabled = false
            menu.addItem(mode)
            addActiveDetails(to: menu)

        case .winding(let secondsLeft):
            let header = NSMenuItem(title: "Work finished — releasing in \(secondsLeft)s",
                                    action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            addActiveDetails(to: menu)
        }

        menu.addItem(.separator())
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit AFK",
                                action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func addActiveDetails(to menu: NSMenu) {
        if !session.busyApps.isEmpty {
            menu.addItem(.separator())
            let label = NSMenuItem(title: "Still working", action: nil, keyEquivalent: "")
            label.isEnabled = false
            menu.addItem(label)
            for app in session.busyApps.prefix(6) {
                let item = NSMenuItem(title: "  \(app.display) — \(app.reason)",
                                      action: nil, keyEquivalent: "")
                item.isEnabled = false
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())
        let stop = NSMenuItem(title: "End Session", action: #selector(cancel), keyEquivalent: "")
        stop.target = self
        menu.addItem(stop)
    }

    private func addModePicker(to menu: NSMenu) {
        let label = NSMenuItem(title: "Stay awake", action: nil, keyEquivalent: "")
        label.isEnabled = false
        menu.addItem(label)

        for mode in ReleaseMode.allCases {
            let item = NSMenuItem(title: "  \(mode.label)",
                                  action: #selector(pickMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            item.state = Prefs.shared.releaseMode == mode ? .on : .off
            if mode == .timer {
                item.title = "  For \(Prefs.shared.timerMinutes) minutes"
            }
            menu.addItem(item)
        }
    }

    @objc private func arm() { session.arm() }
    @objc private func cancel() { session.cancel() }

    @objc private func pickMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = ReleaseMode(rawValue: raw) else { return }
        Prefs.shared.releaseMode = mode
    }

    @objc private func openSettings() {
        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 560),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "AFK Settings"
        window.contentView = NSHostingView(rootView: SettingsView(session: session))
        window.isReleasedWhenClosed = false
        if let frame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame {
            window.setFrameOrigin(CGPoint(x: frame.midX - 230, y: frame.midY - 280))
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = window
    }

    /// Shown when a session ended on its own, so the user is never left
    /// guessing whether their work survived.
    private func present(_ report: SessionReport) {
        let minutes = Int(report.duration / 60)
        let alert = NSAlert()
        alert.messageText = "AFK ended — \(report.endReason.rawValue)"

        var lines = ["Away for \(minutes < 60 ? "\(minutes) min" : "\(minutes / 60)h \(minutes % 60)m")."]
        if !report.appsSeen.isEmpty {
            lines.append("Working: \(report.appsSeen.prefix(5).joined(separator: ", ")).")
        }
        if report.busyAtEnd && report.endReason != .workFinished {
            lines.append("Something was still running when it ended.")
        }
        alert.informativeText = lines.joined(separator: "\n")
        alert.alertStyle = report.busyAtEnd && report.endReason != .workFinished ? .warning : .informational
        alert.runModal()

        session.pendingReport = nil
    }
}
