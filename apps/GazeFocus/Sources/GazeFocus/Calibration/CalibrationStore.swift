import Foundation
import AppKit
import GazeCore

/// Persists calibration, keyed by display arrangement.
///
/// A laptop that docks and undocks has several arrangements, and head angles
/// that map to a 27-inch monitor mean nothing when it is unplugged. Keeping one
/// calibration per arrangement means plugging the monitor back in restores the
/// matching fit instead of demanding a fresh calibration every time.
///
/// Samples are kept, not just the fitted weights, because learning from clicks
/// appends observations and refits — which needs the original data.
final class CalibrationStore {

    static let shared = CalibrationStore()

    private let url: URL
    /// All known arrangements, keyed by layout signature.
    private var profiles: [String: [CalibrationSample]] = [:]

    private(set) var samples: [CalibrationSample] = []
    private(set) var model: GazeModel?
    private(set) var layoutSignature: String = ""

    private struct Payload: Codable {
        var version: Int
        var profiles: [String: [CalibrationSample]]
    }

    /// The pre-v2 format: a single calibration with its layout.
    private struct LegacyPayload: Codable {
        var samples: [CalibrationSample]
        var layoutSignature: String
    }

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                               in: .userDomainMask)[0]
            .appendingPathComponent("GazeFocus", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        url = support.appendingPathComponent("calibration.json")
        load()
        activateCurrentLayout()
    }

    var isCalibrated: Bool { model != nil }

    /// How many other arrangements have been calibrated, for the UI to mention.
    var otherProfileCount: Int {
        max(0, profiles.keys.filter { $0 != Self.currentLayoutSignature() }.count)
    }

    /// Identifies the arrangement by each screen's frame, so both adding a
    /// monitor and moving one select a different profile.
    static func currentLayoutSignature() -> String {
        NSScreen.screens
            .map { "\(Int($0.frame.origin.x)),\(Int($0.frame.origin.y)),\(Int($0.frame.width))x\(Int($0.frame.height))" }
            .sorted()
            .joined(separator: "|")
    }

    /// Switches to the profile for whatever is plugged in now. Called at launch
    /// and whenever the displays change.
    @discardableResult
    func activateCurrentLayout() -> Bool {
        let signature = Self.currentLayoutSignature()
        layoutSignature = signature
        samples = profiles[signature] ?? []

        guard !samples.isEmpty else {
            model = nil
            Log.info("no calibration for layout \(signature)")
            return false
        }
        refit()
        return model != nil
    }

    func replace(with samples: [CalibrationSample]) {
        let signature = Self.currentLayoutSignature()
        layoutSignature = signature
        self.samples = samples
        profiles[signature] = samples
        refit()
        save()
    }

    /// Adds an observation learned from a click and refits.
    func append(_ sample: CalibrationSample) {
        samples.append(sample)
        // Keep the set bounded so the fit stays quick and recent habits win.
        if samples.count > 400 { samples.removeFirst(samples.count - 400) }
        profiles[layoutSignature] = samples
        refit()
        save()
    }

    /// Clears only the arrangement in use, leaving other setups intact.
    func clearCurrentLayout() {
        profiles[layoutSignature] = nil
        samples = []
        model = nil
        save()
    }

    func clearEverything() {
        profiles.removeAll()
        samples = []
        model = nil
        try? FileManager.default.removeItem(at: url)
    }

    private func refit() {
        guard let fitted = GazeModel.fit(samples) else {
            model = nil
            Log.error("refit failed with \(samples.count) samples")
            return
        }
        model = fitted
        Log.info("refit from \(fitted.sampleCount) samples, mean error \(Int(fitted.meanError))pt")
    }

    private func load() {
        guard let data = try? Data(contentsOf: url) else { return }

        if let payload = try? JSONDecoder().decode(Payload.self, from: data) {
            profiles = payload.profiles
            return
        }
        // Carry a pre-v2 file forward rather than discarding the user's work.
        if let legacy = try? JSONDecoder().decode(LegacyPayload.self, from: data) {
            profiles = [legacy.layoutSignature: legacy.samples]
            Log.info("migrated calibration for layout \(legacy.layoutSignature)")
            save()
        }
    }

    private func save() {
        let payload = Payload(version: 2, profiles: profiles)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
