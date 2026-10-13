import Foundation
import CoreGraphics
import GazeCore

/// Simulates a believable rig: yaw and face position in frame both shift with
/// where the user looks, as they do in reality.
func syntheticSample(x: Double, y: Double,
                     desktopWidth: Double = 3840, desktopHeight: Double = 1080,
                     noise: Double = 0) -> CalibrationSample {
    let midX = desktopWidth / 2, midY = desktopHeight / 2
    func jitter() -> Double { noise == 0 ? 0 : Double.random(in: -noise...noise) }

    return CalibrationSample(
        features: [1,
                   (x - midX) / desktopWidth * 0.9 + jitter(),
                   (y - midY) / desktopHeight * 0.3 + jitter(),
                   0.5 - (x - midX) / desktopWidth * 0.2 + jitter(),
                   0.5 - (y - midY) / desktopHeight * 0.06 + jitter()],
        targetX: x, targetY: y, area: 0.08)
}

/// The five-point pattern the calibration flow walks, per display.
func trainingSet(noise: Double = 0.004) -> [CalibrationSample] {
    var samples: [CalibrationSample] = []
    for originX in [0.0, 1920.0] {
        for (fx, fy) in [(0.5, 0.5), (0.12, 0.12), (0.88, 0.12), (0.12, 0.88), (0.88, 0.88)] {
            samples.append(syntheticSample(x: originX + fx * 1920, y: fy * 1080, noise: noise))
        }
    }
    return samples
}

func runGazeModelTests(_ h: Harness) {
    h.suite("GazeModel — fitting") {
        let clean = GazeModel.fit(trainingSet(noise: 0))
        h.check("fits clean data", clean != nil)
        if let clean {
            h.lessThan("clean fit error is small", clean.meanError, 30)
            h.equal("sample count recorded", clean.sampleCount, 10)
        }

        // Fewer samples than features cannot be solved; it must fail rather
        // than return arbitrary weights that look plausible.
        var refusedAll = true
        for count in 0..<HeadPose.featureCount where GazeModel.fit(Array(trainingSet().prefix(count))) != nil {
            refusedAll = false
        }
        h.check("refuses underdetermined fits", refusedAll)

        let malformed = [CalibrationSample(features: [1, 0, 0], targetX: 10, targetY: 10, area: 0.08)]
        h.check("rejects wrong-width feature vectors", GazeModel.fit(malformed + trainingSet()) == nil)

        // One screen yields exactly five points — the minimum. Plenty of users
        // have a single display, so this must still solve.
        var single: [CalibrationSample] = []
        for (fx, fy) in [(0.5, 0.5), (0.12, 0.12), (0.88, 0.12), (0.12, 0.88), (0.88, 0.88)] {
            single.append(syntheticSample(x: fx * 1920, y: fy * 1080, desktopWidth: 1920, noise: 0.003))
        }
        h.check("single-display calibration solves", GazeModel.fit(single) != nil)
    }

    h.suite("GazeModel — prediction") {
        guard let model = GazeModel.fit(trainingSet()) else {
            h.check("fit succeeded", false); return
        }

        var worst = 0.0, correctScreen = 0, count = 0
        for originX in [0.0, 1920.0] {
            for (fx, fy) in [(0.3, 0.4), (0.7, 0.6), (0.5, 0.25), (0.4, 0.75), (0.62, 0.33)] {
                let truth = CGPoint(x: originX + fx * 1920, y: fy * 1080)
                let predicted = model.predict(syntheticSample(x: truth.x, y: truth.y, noise: 0.004).features)
                worst = max(worst, hypot(predicted.x - truth.x, predicted.y - truth.y))
                if (predicted.x < 1920) == (truth.x < 1920) { correctScreen += 1 }
                count += 1
            }
        }
        h.equal("held-out points pick the right display", correctScreen, count)
        h.lessThan("worst-case error stays usable", worst, 220)
    }

    h.suite("GazeModel — robustness") {
        // Every sample identical: the normal matrix is singular. The ridge term
        // must keep elimination from dividing by zero.
        let identical = Array(repeating: syntheticSample(x: 960, y: 540), count: 12)
        if let degenerate = GazeModel.fit(identical) {
            let p = degenerate.predict(identical[0].features)
            h.check("degenerate input yields finite output", p.x.isFinite && p.y.isFinite)
        } else {
            h.check("degenerate input handled (refused)", true)
        }

        // Four times the usual jitter — a restless user in poor light.
        if let noisy = GazeModel.fit(trainingSet(noise: 0.016)) {
            var correct = 0, total = 0
            for originX in [0.0, 1920.0] {
                for fx in [0.25, 0.5, 0.75] {
                    let truth = CGPoint(x: originX + fx * 1920, y: 540)
                    let p = noisy.predict(syntheticSample(x: truth.x, y: truth.y, noise: 0.016).features)
                    if (p.x < 1920) == (truth.x < 1920) { correct += 1 }
                    total += 1
                }
            }
            h.equal("noisy data still picks the right display", correct, total)
        } else {
            h.check("noisy fit succeeded", false)
        }

        // Extreme feature values must not produce NaN that would later be used
        // as a screen coordinate.
        if let model = GazeModel.fit(trainingSet()) {
            let wild = model.predict([1, 50, -50, 900, -900])
            h.check("extreme input stays finite", wild.x.isFinite && wild.y.isFinite)
        }
    }

    h.suite("GazeModel — distance drift") {
        guard let model = GazeModel.fit(trainingSet()) else {
            h.check("fit succeeded", false); return
        }
        let reference = model.referenceArea
        // Area scales with the square of apparent size: 4x area is 2x closer.
        h.close("4x area reads as 2x closer", model.distanceDrift(area: reference * 4), 2.0, 0.01)
        h.close("reference area reads as unchanged", model.distanceDrift(area: reference), 1.0, 0.01)
        h.close("quarter area reads as half", model.distanceDrift(area: reference / 4), 0.5, 0.01)
        h.close("zero area does not produce NaN", model.distanceDrift(area: 0), 1.0, 0.0001)
    }

    h.suite("GazeModel — persistence") {
        guard let model = GazeModel.fit(trainingSet()) else {
            h.check("fit succeeded", false); return
        }
        let probe = syntheticSample(x: 1200, y: 600).features
        let before = model.predict(probe)
        do {
            let decoded = try JSONDecoder().decode(GazeModel.self, from: JSONEncoder().encode(model))
            let after = decoded.predict(probe)
            h.close("x survives a save/load round trip", after.x, before.x, 0.0001)
            h.close("y survives a save/load round trip", after.y, before.y, 0.0001)
        } catch {
            h.check("model encodes and decodes", false, "\(error)")
        }
    }
}
