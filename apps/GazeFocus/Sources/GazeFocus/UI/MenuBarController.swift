import AppKit
import SwiftUI
import Combine
import Carbon.HIToolbox

/// The eye icon, its menu, and the ⇧⌘G pause shortcut.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let engine: GazeEngine
    private let calibration: CalibrationController
    private let overlay = GazeOverlay()

    private var cancellables: Set<AnyCancellable> = []
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var hotKeyRef: EventHotKeyRef?

    init(engine: GazeEngine, calibration: CalibrationController) {
        self.engine = engine
        self.calibration = calibration
        super.init()

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        engine.$status
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.render($0) }
            .store(in: &cancellables)

        // The overlay follows the live gaze point only while enabled.
        engine.$gazePoint
            .receive(on: RunLoop.main)
            .sink { [weak self] point in
                guard Prefs.shared.showGazeDot else { return }
                self?.overlay.update(to: point)
            }
            .store(in: &cancellables)

        registerHotKey()
    }

    private func render(_ status: GazeStatus) {
        guard let button = statusItem.button else { return }

        let symbol: String
        switch status {
        case .tracking:          symbol = "eye.fill"
        case .paused:            symbol = "eye.slash"
        case .noFace:            symbol = "eye.trianglebadge.exclamationmark"
        case .waiting:           symbol = "eye"
        case .needsCamera,
             .needsAccessibility,
             .needsCalibration:  symbol = "exclamationmark.triangle"
        }

        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "GazeFocus")
        button.image?.isTemplate = true
        button.toolTip = summary(for: status)

        overlay.setVisible(Prefs.shared.showGazeDot && status.isActive)
    }

    private func summary(for status: GazeStatus) -> String {
        switch status {
        case .needsCamera:        return "Camera access needed"
        case .needsAccessibility: return "Accessibility access needed"
        case .needsCalibration:   return "Not calibrated yet"
        case .paused:             return "Paused"
        case .noFace:             return "Can't see you"
        case .waiting(let why):   return "Holding — \(why)"
        case .tracking(let name): return "Watching \(name)"
        }
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let header = NSMenuItem(title: summary(for: engine.status), action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        switch engine.status {
        case .needsCamera, .needsAccessibility, .needsCalibration:
            let setup = NSMenuItem(title: "Finish Setup…", action: #selector(openOnboarding), keyEquivalent: "")
            setup.target = self
            menu.addItem(setup)

            // The common case for being stuck here is a permission granted
            // after launch, which only a relaunch will surface.
            if case .needsAccessibility = engine.status {
                let relaunch = NSMenuItem(title: "Relaunch GazeFocus",
                                          action: #selector(relaunchApp), keyEquivalent: "")
                relaunch.target = self
                relaunch.toolTip = "Use this if you have already allowed Accessibility"
                menu.addItem(relaunch)
            }

        default:
            let toggle = NSMenuItem(
                title: engine.isPaused ? "Resume" : "Pause",
                action: #selector(togglePause), keyEquivalent: "g")
            toggle.keyEquivalentModifierMask = [.command, .shift]
            toggle.target = self
            menu.addItem(toggle)

            if engine.needsRecalibration {
                let warn = NSMenuItem(title: "⚠︎ Accuracy has drifted", action: nil, keyEquivalent: "")
                warn.isEnabled = false
                menu.addItem(warn)
            }

            let recalibrate = NSMenuItem(title: "Recalibrate…", action: #selector(startCalibration), keyEquivalent: "")
            recalibrate.target = self
            recalibrate.isEnabled = !calibration.isRunning
            menu.addItem(recalibrate)

            let dot = NSMenuItem(title: "Show Gaze Dot", action: #selector(toggleDot), keyEquivalent: "")
            dot.target = self
            dot.state = Prefs.shared.showGazeDot ? .on : .off
            menu.addItem(dot)
        }

        menu.addItem(.separator())
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit GazeFocus",
                                action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    @objc private func togglePause() { engine.isPaused.toggle() }

    @objc private func relaunchApp() { Relaunch.now() }

    @objc private func toggleDot() {
        Prefs.shared.showGazeDot.toggle()
        overlay.setVisible(Prefs.shared.showGazeDot && engine.status.isActive)
    }

    @objc private func startCalibration() {
        // The engine must release the camera before calibration can claim it.
        let wasPaused = engine.isPaused
        engine.isPaused = true

        calibration.start { [weak self] success, message in
            guard let self else { return }
            engine.isPaused = wasPaused
            if success {
                engine.recalibrated()
                notify(title: "Calibration complete", body: "GazeFocus is tracking again.")
            } else if let message {
                notify(title: "Calibration stopped", body: message)
            }
        }
    }

    @objc private func openSettings() {
        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = SettingsView(engine: engine, calibration: calibration) { [weak self] in
            self?.startCalibration()
        }
        settingsWindow = present(view, title: "GazeFocus Settings", width: 500, height: 620)
    }

    @objc func openOnboarding() {
        if let onboardingWindow {
            onboardingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = OnboardingView(engine: engine, calibration: calibration) { [weak self] in
            self?.onboardingWindow?.close()
            self?.onboardingWindow = nil
            self?.engine.recalibrated()
            self?.engine.start()
        }
        onboardingWindow = present(view, title: "Set up GazeFocus", width: 520, height: 420)
    }

    private func present<V: View>(_ view: V, title: String,
                                  width: CGFloat, height: CGFloat) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                              styleMask: [.titled, .closable],
                              backing: .buffered, defer: false)
        window.title = title
        window.contentView = NSHostingView(rootView: view)
        window.isReleasedWhenClosed = false

        // `center()` picks the main screen, which on a multi-display Mac with a
        // display at negative coordinates can land the window outside every
        // screen — where the window server treats it as off-screen and it
        // simply never appears. Positioning against a known screen avoids that.
        let host = NSScreen.main ?? NSScreen.screens.first
        if let frame = host?.visibleFrame {
            window.setFrameOrigin(CGPoint(
                x: frame.midX - width / 2,
                y: frame.midY - height / 2
            ))
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return window
    }

    private func notify(title: String, body: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = body
        alert.alertStyle = .informational
        alert.runModal()
    }

    // MARK: - Global shortcut

    /// ⇧⌘G toggles pause from anywhere. Carbon's hot-key API is used because it
    /// works without the app being frontmost and needs no extra permission.
    private func registerHotKey() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))

        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let userData else { return noErr }
            let controller = Unmanaged<MenuBarController>.fromOpaque(userData).takeUnretainedValue()
            Task { @MainActor in controller.engine.isPaused.toggle() }
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), nil)

        let hotKeyID = EventHotKeyID(signature: OSType(0x47415A45), id: 1) // 'GAZE'
        RegisterEventHotKey(UInt32(kVK_ANSI_G),
                            UInt32(cmdKey | shiftKey),
                            hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }
}

private extension GazeStatus {
    var isActive: Bool {
        switch self {
        case .tracking, .waiting, .noFace: return true
        default: return false
        }
    }
}
