import Foundation
import AppKit

/// An app judged to be doing real work right now.
public struct BusyApp: Identifiable, Equatable {
    public let id: String
    public let display: String
    public let category: AppCategory
    public let cpuPercent: Double
    public let diskKBps: Double
    public let netKBps: Double
    /// How long this app has been continuously busy.
    public let busyFor: TimeInterval

    public static func == (a: BusyApp, b: BusyApp) -> Bool { a.id == b.id }

    public var reason: String {
        var parts: [String] = []
        if cpuPercent >= 1 { parts.append(String(format: "%.0f%% CPU", cpuPercent)) }
        if diskKBps >= 1 { parts.append(String(format: "%.0f KB/s disk", diskKBps)) }
        if netKBps >= 1 { parts.append(String(format: "%.0f KB/s net", netKBps)) }
        return parts.isEmpty ? "active" : parts.joined(separator: " · ")
    }
}

/// Differences successive samples into rates, then requires a run of busy
/// readings before an app counts — this is what makes a brief spike from
/// opening a file or loading a page fail to hold the machine awake.
public final class ActivityMonitor {

    public init() {}

    /// Identity is the bundle id when there is one, else the executable name,
    /// so every process of a multi-process app collapses into one row.
    private struct Accumulator {
        var display: String
        var category: AppCategory
        var cpuFloor: Double?
        var cpuNanos: UInt64 = 0
        var diskBytes: UInt64 = 0
        var netBytes: UInt64 = 0
    }

    private let processSampler = ProcessSampler()
    private let networkSampler = NetworkSampler()

    private var previous: [String: Accumulator] = [:]
    private var previousAt: Date?
    /// When each app most recently *started* being continuously busy.
    private var busySince: [String: Date] = [:]

    public private(set) var lastBusy: [BusyApp] = []

    /// Apps over threshold but not yet sustained long enough to count.
    /// Surfaced for diagnostics so a threshold problem is distinguishable
    /// from an app that is simply still inside its sustain window.
    public private(set) var lastCandidates: [BusyApp] = []

    /// Apps whose own power assertions are holding sleep, when that is honoured.
    public private(set) var assertingApps: [String] = []

    public func tick(_ thresholds: ActivityThresholds) -> [BusyApp] {
        networkSampler.refresh()
        let netTotals = networkSampler.currentTotals()
        let raw = processSampler.sample()
        let now = Date()

        let current = aggregate(raw, netTotals: netTotals)
        defer { previous = current; previousAt = now }

        guard let previousAt, let elapsed = elapsedSeconds(from: previousAt, to: now) else {
            return []
        }

        let ignored = thresholds.ignored
        var busy: [BusyApp] = []
        var candidates: [BusyApp] = []
        var stillBusy: Set<String> = []

        for (key, accumulator) in current {
            guard !ignored.contains(key) else { continue }
            guard let before = previous[key] else { continue }

            let cpuPercent = Double(accumulator.cpuNanos &- min(before.cpuNanos, accumulator.cpuNanos))
                / elapsed / 1_000_000_000 * 100
            let diskKBps = Double(accumulator.diskBytes &- min(before.diskBytes, accumulator.diskBytes))
                / elapsed / 1024
            let netKBps = Double(accumulator.netBytes &- min(before.netBytes, accumulator.netBytes))
                / elapsed / 1024

            let cpuBar = accumulator.cpuFloor ?? thresholds.cpuPercent
            let isBusy = cpuPercent >= cpuBar
                || diskKBps >= thresholds.diskKBps
                || netKBps >= thresholds.netKBps

            guard isBusy else { continue }
            stillBusy.insert(key)

            let since = busySince[key] ?? now
            busySince[key] = since
            let busyFor = now.timeIntervalSince(since)

            let observed = BusyApp(
                id: key, display: accumulator.display, category: accumulator.category,
                cpuPercent: cpuPercent, diskKBps: diskKBps, netKBps: netKBps, busyFor: busyFor
            )
            candidates.append(observed)

            // The sustain window is the spike filter: short bursts never qualify.
            guard busyFor >= Double(thresholds.sustainSeconds) else { continue }
            busy.append(observed)
        }

        // Anything that stopped being busy loses its streak immediately.
        busySince = busySince.filter { stillBusy.contains($0.key) }

        if thresholds.honorAppAssertions {
            assertingApps = PowerAssertionReader.appsPreventingSleep()
                .filter { !ignored.contains($0) }
        } else {
            assertingApps = []
        }

        lastCandidates = candidates.sorted { $0.cpuPercent > $1.cpuPercent }
        lastBusy = busy.sorted { $0.cpuPercent + $0.netKBps > $1.cpuPercent + $1.netKBps }
        return lastBusy
    }

    /// Rejects intervals distorted by the machine having been asleep.
    private func elapsedSeconds(from start: Date, to end: Date) -> Double? {
        let elapsed = end.timeIntervalSince(start)
        guard elapsed > 0.2, elapsed < 120 else { return nil }
        return elapsed
    }

    private func aggregate(_ raw: [RawSample], netTotals: [pid_t: UInt64]) -> [String: Accumulator] {
        var result: [String: Accumulator] = [:]
        for sample in raw {
            let entry = AppCatalog.lookup(bundleID: sample.bundleID, executable: sample.executable)
            let key = sample.bundleID ?? sample.executable

            var accumulator = result[key] ?? Accumulator(
                display: entry?.display ?? sample.displayName,
                category: entry?.category ?? .other,
                cpuFloor: entry?.cpuFloor
            )
            accumulator.cpuNanos &+= sample.cpuNanos
            accumulator.diskBytes &+= sample.diskBytes
            accumulator.netBytes &+= netTotals[sample.pid] ?? 0
            result[key] = accumulator
        }
        return result
    }

    public func reset() {
        previous.removeAll()
        previousAt = nil
        busySince.removeAll()
        lastBusy = []
        lastCandidates = []
    }
}
