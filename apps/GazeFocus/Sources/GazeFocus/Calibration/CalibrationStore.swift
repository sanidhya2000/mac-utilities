import Foundation
import AppKit
import GazeCore

/// Persists calibration samples and the model fitted from them.
///
/// Samples are kept, not just the fitted weights, because learning from clicks
/// appends new observations and refits — which needs the original data.
final class CalibrationStore {

    static let shared = CalibrationStore()

    private let url: URL
    private(set) var samples: [CalibrationSample] = []
    private(set) var model: GazeModel?

    /// The display layout the calibration was captured against. If monitors are
    /// rearranged the old mapping is meaningless, so it is discarded.
    private(set) var layoutSignature: String = ""

    private struct Payload: Codable {
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
    }

    var isCalibrated: Bool { model != nil && layoutSignature == Self.currentLayoutSignature() }

    /// Identifies the arrangement by each screen's frame, so both adding a
    /// monitor and moving one invalidate the fit.
    static func currentLayoutSignature() -> String {
        NSScreen.screens
            .map { "\(Int($0.frame.origin.x)),\(Int($0.frame.origin.y)),\(Int($0.frame.width))x\(Int($0.frame.height))" }
            .sorted()
            .joined(separator: "|")
    }

    func replace(with samples: [CalibrationSample]) {
        self.samples = samples
        self.layoutSignature = Self.currentLayoutSignature()
        refit()
        save()
    }

    /// Adds an observation learned from a click and refits.
    func append(_ sample: CalibrationSample) {
        samples.append(sample)
        // Keep the set bounded so the fit stays quick and recent habits win.
        if samples.count > 400 { samples.removeFirst(samples.count - 400) }
        refit()
        save()
    }

    func clear() {
        samples = []
        model = nil
        layoutSignature = ""
        try? FileManager.default.removeItem(at: url)
    }

    private func refit() {
        guard let fitted = GazeModel.fit(samples) else {
            Log.error("calibration refit failed with \(samples.count) samples")
            return
        }
        model = fitted
        Log.info("refit from \(fitted.sampleCount) samples, mean error \(Int(fitted.meanError))pt")
    }

    private func load() {
        guard let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(Payload.self, from: data)
        else { return }
        samples = payload.samples
        layoutSignature = payload.layoutSignature
        refit()
    }

    private func save() {
        let payload = Payload(samples: samples, layoutSignature: layoutSignature)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
