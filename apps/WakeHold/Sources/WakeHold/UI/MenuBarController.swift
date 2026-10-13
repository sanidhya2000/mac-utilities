import AppKit
import SwiftUI
import Combine
import PowerCore

/// The cup icon and its menu. The icon alone tells the story: filled while
/// sleep is held, outlined when the Mac is free to drift off.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let engine: WakeEngine
    private var cancellables: Set<AnyCancellable> = []
    private var settingsWindow: NSWindow?

    init(engine: WakeEngine) {
        self.engine = engine
        super.init()

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        engine.$status
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.render($0) }
            .store(in: &cancellables)
    }

    private func render(_ status: EngineStatus) {
        guard let button = statusItem.button else { return }

        let symbol: String
        switch status {
        case .holding:  symbol = "cup.and.saucer.fill"
        case .winding:  symbol = "cup.and.saucer.fill"
        case .idle:     symbol = "cup.and.saucer"
        case .blocked:  symbol = "cup.and.saucer"
        case .paused:   symbol = "pause.circle"
        }

        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "WakeHold")
        button.image?.isTemplate = true
        button.appearsDisabled = !status.holdsSleep && status != .paused
        button.toolTip = summary(for: status)
    }

    private func summary(for status: EngineStatus) -> String {
        switch status {
        case .idle:                    return "Idle — your Mac can sleep"
        case .paused:                  return "Paused"
        case .blocked(let reason):     return "Not holding — \(reason)"
        case .winding(let seconds):    return "Work stopped — releasing in \(seconds)s"
        case .holding(let apps):
            guard let first = apps.first else { return "Holding sleep" }
            return apps.count == 1 ? "Awake for \(first)"
                                   : "Awake for \(first) +\(apps.count - 1) more"
        }
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let header = NSMenuItem(title: summary(for: engine.status), action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        if !engine.busyApps.isEmpty {
            menu.addItem(.separator())
            let label = NSMenuItem(title: "Working now", action: nil, keyEquivalent: "")
            label.isEnabled = false
            menu.addItem(label)

            for app in engine.busyApps.prefix(8) {
                let item = NSMenuItem(
                    title: "  \(app.display) — \(app.reason)",
                    action: #selector(ignoreApp(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = app
                item.image = NSImage(systemSymbolName: app.category.symbol, accessibilityDescription: nil)
                item.toolTip = "Click to stop watching \(app.display)"
                menu.addItem(item)
            }
        }

        if !engine.assertingApps.isEmpty {
            menu.addItem(.separator())
            let label = NSMenuItem(title: "Asked to stay awake", action: nil, keyEquivalent: "")
            label.isEnabled = false
            menu.addItem(label)
            for name in engine.assertingApps.prefix(5) {
                let item = NSMenuItem(title: "  \(name)", action: nil, keyEquivalent: "")
                item.isEnabled = false
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())

        let toggle = NSMenuItem(
            title: engine.isPaused ? "Resume" : "Pause",
            action: #selector(togglePause), keyEquivalent: "p")
        toggle.target = self
        menu.addItem(toggle)

        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit WakeHold", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    @objc private func ignoreApp(_ sender: NSMenuItem) {
        guard let app = sender.representedObject as? BusyApp else { return }
        engine.ignore(app)
    }

    @objc private func togglePause() { engine.isPaused.toggle() }

    @objc private func openSettings() {
        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 560),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "WakeHold Settings"
        window.contentView = NSHostingView(rootView: SettingsView(engine: engine))
        window.center()
        window.isReleasedWhenClosed = false
        settingsWindow = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
