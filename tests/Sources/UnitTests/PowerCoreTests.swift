import Foundation
import PowerCore

func runPowerCoreTests(_ h: Harness) {

    h.suite("AppCatalog — recognition") {
        h.check("finds an app by bundle id",
                AppCatalog.lookup(bundleID: "com.apple.FinalCut", executable: "")?.display == "Final Cut Pro")
        h.check("bundle id match is case-insensitive",
                AppCatalog.lookup(bundleID: "COM.APPLE.FINALCUT", executable: "")?.display == "Final Cut Pro")
        h.check("finds a CLI tool by executable name",
                AppCatalog.lookup(bundleID: nil, executable: "ffmpeg")?.display == "ffmpeg")
        h.check("bundle id wins over executable",
                AppCatalog.lookup(bundleID: "com.apple.dt.Xcode", executable: "ffmpeg")?.display == "Xcode")
        h.check("unknown app is not recognised",
                AppCatalog.lookup(bundleID: "com.example.nothing", executable: "nothing") == nil)

        // Long-running jobs sit at a steady, modest CPU; a floor that high
        // would make them invisible.
        let ffmpeg = AppCatalog.lookup(bundleID: nil, executable: "ffmpeg")
        h.check("render tools get a lower CPU floor", (ffmpeg?.cpuFloor ?? 99) < 15)

        // AI agents idle between bursts, so their floor must be lower still.
        let claude = AppCatalog.lookup(bundleID: nil, executable: "claude")
        h.check("AI agents get the lowest floor", (claude?.cpuFloor ?? 99) <= 3)
        h.equal("AI agents are categorised", claude?.category, .aiAgents)

        h.check("catalog covers every category",
                Set(AppCatalog.entries.map(\.category)).count >= 5)
        h.check("catalog has a useful number of apps", AppCatalog.entries.count >= 30)

        // A duplicate identifier would make recognition order-dependent.
        let allBundleIDs = AppCatalog.entries.flatMap { $0.bundleIDs.map { $0.lowercased() } }
        h.equal("no duplicate bundle ids", allBundleIDs.count, Set(allBundleIDs).count)
    }

    h.suite("PowerPolicy — when holding is refused") {
        let policy = PowerPolicy(batteryFloor: 20, respectLowPowerMode: true, keepScreenOn: false)

        let healthy = PowerState(onAC: false, percentage: 80, lowPowerMode: false, hasBattery: true)
        h.check("healthy battery allows holding", healthy.blockedReason(policy) == nil)

        let flat = PowerState(onAC: false, percentage: 10, lowPowerMode: false, hasBattery: true)
        h.check("low battery blocks holding", flat.blockedReason(policy) != nil)

        // Plugged in, the charge level is irrelevant.
        let charging = PowerState(onAC: true, percentage: 5, lowPowerMode: false, hasBattery: true)
        h.check("low battery on AC still allows holding", charging.blockedReason(policy) == nil)

        // Desktops report no battery and must never be blocked by the floor.
        let desktop = PowerState(onAC: true, percentage: 100, lowPowerMode: false, hasBattery: false)
        h.check("desktops are never battery-blocked", desktop.blockedReason(policy) == nil)
        h.check("desktop batteryTooLow is false", !desktop.batteryTooLow(floor: 50))

        let lowPower = PowerState(onAC: true, percentage: 100, lowPowerMode: true, hasBattery: true)
        h.check("Low Power Mode blocks holding", lowPower.blockedReason(policy) != nil)

        let ignoringLowPower = PowerPolicy(batteryFloor: 20, respectLowPowerMode: false, keepScreenOn: false)
        h.check("Low Power Mode can be overridden", lowPower.blockedReason(ignoringLowPower) == nil)

        // Exactly at the floor is not below it.
        let atFloor = PowerState(onAC: false, percentage: 20, lowPowerMode: false, hasBattery: true)
        h.check("exactly at the floor is allowed", atFloor.blockedReason(policy) == nil)

        let zeroFloor = PowerPolicy(batteryFloor: 0, respectLowPowerMode: false, keepScreenOn: false)
        let nearlyDead = PowerState(onAC: false, percentage: 1, lowPowerMode: false, hasBattery: true)
        h.check("a zero floor disables the check", nearlyDead.blockedReason(zeroFloor) == nil)
    }

    h.suite("SleepController — assertion lifecycle") {
        let controller = SleepController()
        h.check("starts released", !controller.isHolding)

        controller.hold(reason: "unit test", keepScreenOn: false)
        h.check("holds after hold()", controller.isHolding)
        h.check("assertion is visible to the system", systemSeesAssertion(named: "unit test"))

        // Renaming must not drop and recreate the assertion.
        controller.hold(reason: "unit test renamed", keepScreenOn: false)
        h.check("still holding after a rename", controller.isHolding)
        h.check("system shows the new reason", systemSeesAssertion(named: "unit test renamed"))

        controller.release()
        h.check("releases cleanly", !controller.isHolding)
        h.check("assertion is gone from the system", !systemSeesAssertion(named: "unit test renamed"))

        // Releasing twice must not trap or corrupt state.
        controller.release()
        h.check("double release is safe", !controller.isHolding)

        // And it must be reusable afterwards.
        controller.hold(reason: "second run", keepScreenOn: false)
        h.check("can hold again after release", controller.isHolding)
        controller.release()
        h.check("final release", !controller.isHolding)
    }

    h.suite("ActivityThresholds — defaults") {
        let defaults = ActivityThresholds()
        h.check("has a non-zero CPU bar", defaults.cpuPercent > 0)
        h.check("requires sustained activity", defaults.sustainSeconds >= 1)
        h.check("honours other apps' assertions by default", defaults.honorAppAssertions)
        h.check("ignores nothing by default", defaults.ignored.isEmpty)

        let custom = ActivityThresholds(cpuPercent: 50, sustainSeconds: 30, ignored: ["com.example.vm"])
        h.close("custom CPU bar is kept", custom.cpuPercent, 50, 0.001)
        h.equal("custom sustain is kept", custom.sustainSeconds, 30)
        h.check("ignore list is kept", custom.ignored.contains("com.example.vm"))
    }

    h.suite("ActivityMonitor — sampling") {
        let monitor = ActivityMonitor()
        let thresholds = ActivityThresholds(cpuPercent: 0.01, diskKBps: 999999,
                                            netKBps: 999999, sustainSeconds: 1)

        // The first tick has no previous sample to difference against, so it
        // must report nothing rather than treating totals as rates.
        h.check("first tick reports nothing", monitor.tick(thresholds).isEmpty)

        Thread.sleep(forTimeInterval: 1.2)
        _ = monitor.tick(thresholds)
        Thread.sleep(forTimeInterval: 1.2)
        let busy = monitor.tick(thresholds)

        // With a near-zero CPU bar, something on a live machine must register.
        h.check("detects activity with a low bar", !busy.isEmpty)
        h.check("every reported app has an identity", busy.allSatisfy { !$0.id.isEmpty })
        h.check("every reported app has a display name", busy.allSatisfy { !$0.display.isEmpty })
        h.check("CPU percentages are finite", busy.allSatisfy { $0.cpuPercent.isFinite })
        h.check("CPU percentages are not negative", busy.allSatisfy { $0.cpuPercent >= 0 })
        h.check("reason strings are non-empty", busy.allSatisfy { !$0.reason.isEmpty })

        // A single core cannot exceed 100%, but multi-process apps aggregate,
        // so the ceiling is core count — a wildly larger figure means the mach
        // timebase conversion has regressed.
        let cores = Double(ProcessInfo.processInfo.activeProcessorCount)
        h.check("CPU stays within physical limits",
                busy.allSatisfy { $0.cpuPercent <= cores * 100 * 1.5 },
                "max was \(busy.map(\.cpuPercent).max() ?? 0)% across \(Int(cores)) cores")

        // An impossible bar must yield nothing.
        let unreachable = ActivityThresholds(cpuPercent: 1_000_000, diskKBps: 1_000_000,
                                             netKBps: 1_000_000, sustainSeconds: 1)
        h.check("an unreachable bar detects nothing", monitor.tick(unreachable).isEmpty)

        // Ignoring everything currently busy must silence it.
        let ignoringAll = ActivityThresholds(cpuPercent: 0.01, diskKBps: 999999, netKBps: 999999,
                                             sustainSeconds: 1,
                                             ignored: Set(monitor.lastCandidates.map(\.id)))
        h.check("the ignore list suppresses apps", monitor.tick(ignoringAll).isEmpty)

        monitor.reset()
        h.check("reset clears results", monitor.lastBusy.isEmpty)
        h.check("tick after reset reports nothing", monitor.tick(thresholds).isEmpty)
    }

    h.suite("ActivityMonitor — sustain filter") {
        let monitor = ActivityMonitor()
        // A long sustain window means nothing can qualify in a short run, even
        // with a bar low enough that everything is over it. This is the filter
        // that stops a brief spike from holding the machine awake.
        let longSustain = ActivityThresholds(cpuPercent: 0.01, diskKBps: 999999,
                                             netKBps: 999999, sustainSeconds: 600)
        _ = monitor.tick(longSustain)
        Thread.sleep(forTimeInterval: 1.2)
        _ = monitor.tick(longSustain)
        Thread.sleep(forTimeInterval: 1.2)
        let qualified = monitor.tick(longSustain)

        h.check("nothing qualifies inside the sustain window", qualified.isEmpty)
        h.check("but candidates were still observed", !monitor.lastCandidates.isEmpty)
    }

    h.suite("PowerAssertionReader") {
        let apps = PowerAssertionReader.appsPreventingSleep()
        h.check("returns without error", apps.count >= 0)
        h.check("entries are non-empty strings", apps.allSatisfy { !$0.isEmpty })

        // Our own assertion must be excluded, or an app would see itself as a
        // reason to stay awake and hold forever.
        let controller = SleepController()
        controller.hold(reason: "self-exclusion probe", keepScreenOn: false)
        let during = PowerAssertionReader.appsPreventingSleep()
        h.check("excludes our own assertion",
                !during.contains { $0.contains("self-exclusion probe") })
        controller.release()
    }
}

/// Reads assertions back from the system to confirm what was actually created,
/// rather than trusting the controller's own flag.
private func systemSeesAssertion(named name: String) -> Bool {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
    task.arguments = ["-g", "assertions"]
    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = FileHandle.nullDevice
    guard (try? task.run()) != nil else { return false }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    task.waitUntilExit()
    return String(data: data, encoding: .utf8)?.contains(name) ?? false
}
