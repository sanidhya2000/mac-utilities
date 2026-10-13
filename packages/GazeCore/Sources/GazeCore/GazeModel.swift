import Foundation
import CoreGraphics

/// One calibration observation: where the dot was, and how the head looked.
public struct CalibrationSample: Codable {
    public let features: [Double]
    /// Target point in global display coordinates.
    public let targetX: Double
    public let targetY: Double
    /// Face area at capture time, used to detect distance drift later.
    public let area: Double

    public init(features: [Double], targetX: Double, targetY: Double, area: Double) {
        self.features = features
        self.targetX = targetX
        self.targetY = targetY
        self.area = area
    }
}

/// Maps head pose to a point on the desktop.
///
/// Rather than classifying "which screen", the model predicts a continuous
/// coordinate in the global display space. Screen, window and pane all then
/// fall out of hit-testing that one point, so the same fit drives every level
/// of focus switching.
///
/// The fit is ridge regression — ordinary least squares plus a small penalty.
/// Calibration yields only a handful of points, often nearly collinear when
/// displays sit in a row, and unregularised least squares turns that into wild
/// extrapolation. The penalty costs a little accuracy and buys stability.
public struct GazeModel: Codable {

    /// Weights mapping the feature vector to x and y.
    private let weightsX: [Double]
    private let weightsY: [Double]
    /// Mean face area across calibration, the baseline for drift detection.
    public let referenceArea: Double
    /// Mean residual error in points — reported to the user as fit quality.
    public let meanError: Double
    public let sampleCount: Int

    public static let ridgeLambda = 1e-4

    public func predict(_ features: [Double]) -> CGPoint {
        CGPoint(x: dot(weightsX, features), y: dot(weightsY, features))
    }

    /// How far the user has moved from their calibrated distance, as a ratio.
    /// Face area scales with the square of apparent size, hence the square root.
    public func distanceDrift(area: Double) -> Double {
        guard referenceArea > 0, area > 0 else { return 1 }
        return (area / referenceArea).squareRoot()
    }

    /// Fits a model, or returns nil when there are too few samples to solve.
    public static func fit(_ samples: [CalibrationSample]) -> GazeModel? {
        guard samples.count >= HeadPose.featureCount else { return nil }

        let rows = samples.map(\.features)
        guard let wx = solveRidge(rows: rows, targets: samples.map(\.targetX)),
              let wy = solveRidge(rows: rows, targets: samples.map(\.targetY))
        else { return nil }

        var totalError = 0.0
        for sample in samples {
            let dx = dot(wx, sample.features) - sample.targetX
            let dy = dot(wy, sample.features) - sample.targetY
            totalError += (dx * dx + dy * dy).squareRoot()
        }

        let areas = samples.map(\.area)
        return GazeModel(
            weightsX: wx,
            weightsY: wy,
            referenceArea: areas.reduce(0, +) / Double(areas.count),
            meanError: totalError / Double(samples.count),
            sampleCount: samples.count
        )
    }

    // MARK: - Linear algebra

    private static func dot(_ a: [Double], _ b: [Double]) -> Double {
        zip(a, b).reduce(0) { $0 + $1.0 * $1.1 }
    }

    private func dot(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count else { return 0 }
        return zip(a, b).reduce(0) { $0 + $1.0 * $1.1 }
    }

    /// Solves (XᵀX + λI)w = Xᵀy by Gaussian elimination with partial pivoting.
    private static func solveRidge(rows: [[Double]], targets: [Double]) -> [Double]? {
        let n = HeadPose.featureCount
        guard rows.count == targets.count, rows.allSatisfy({ $0.count == n }) else { return nil }

        var normal = [[Double]](repeating: [Double](repeating: 0, count: n + 1), count: n)
        for (row, target) in zip(rows, targets) {
            for i in 0..<n {
                for j in 0..<n { normal[i][j] += row[i] * row[j] }
                normal[i][n] += row[i] * target
            }
        }
        // The intercept term is left unpenalised so the fit can still centre itself.
        for i in 1..<n { normal[i][i] += ridgeLambda }

        for pivot in 0..<n {
            var best = pivot
            for candidate in (pivot + 1)..<n
            where abs(normal[candidate][pivot]) > abs(normal[best][pivot]) {
                best = candidate
            }
            normal.swapAt(pivot, best)

            let head = normal[pivot][pivot]
            guard abs(head) > 1e-12 else { return nil }

            for row in (pivot + 1)..<n {
                let factor = normal[row][pivot] / head
                guard factor != 0 else { continue }
                for column in pivot...n { normal[row][column] -= factor * normal[pivot][column] }
            }
        }

        var weights = [Double](repeating: 0, count: n)
        for row in stride(from: n - 1, through: 0, by: -1) {
            var value = normal[row][n]
            for column in (row + 1)..<n { value -= normal[row][column] * weights[column] }
            weights[row] = value / normal[row][row]
        }
        return weights.allSatisfy(\.isFinite) ? weights : nil
    }
}
