import Foundation
import Vision
import CoreVideo

/// One reading of where the head is and which way it is turned.
struct HeadPose {
    /// Left/right rotation in radians; positive is turning to the user's left.
    let yaw: Double
    /// Up/down rotation in radians.
    let pitch: Double
    let roll: Double
    /// Face centre within the frame, 0–1, origin bottom-left.
    let centerX: Double
    let centerY: Double
    /// Face box area as a fraction of the frame — a proxy for distance, used to
    /// notice when someone has moved closer or further than when they calibrated.
    let area: Double
    let timestamp: Date

    /// The feature vector the screen mapping is fitted against. Yaw alone is a
    /// weak signal because people turn their eyes as well as their head, so the
    /// face's position in frame is included — it shifts measurably when someone
    /// looks across to another display.
    var features: [Double] { [1, yaw, pitch, centerX, centerY] }

    static let featureCount = 5
}

/// Runs Vision's face-landmark request over camera frames and smooths the
/// result. Everything stays on-device; Vision never touches the network.
final class HeadPoseTracker {

    private let sequenceHandler = VNSequenceRequestHandler()

    /// Exponential smoothing factor. Low enough to kill per-frame jitter,
    /// high enough that a real head turn still lands within ~100ms.
    private let smoothing = 0.35
    private var smoothed: HeadPose?

    /// Frames in a row with no face. Used to stop acting on a stale pose when
    /// the user walks away.
    private(set) var missingFrames = 0

    var onPose: ((HeadPose?) -> Void)?

    func process(_ pixelBuffer: CVPixelBuffer) {
        let request = VNDetectFaceRectanglesRequest()
        // Revision 3 reports pitch as well as yaw and roll.
        request.revision = VNDetectFaceRectanglesRequestRevision3

        do {
            try sequenceHandler.perform([request], on: pixelBuffer, orientation: .leftMirrored)
        } catch {
            Log.error("vision request failed: \(error.localizedDescription)")
            return
        }

        guard let face = bestFace(in: request.results) else {
            missingFrames += 1
            // A couple of dropped frames is normal — blinking, a hand passing by.
            if missingFrames > 8 {
                smoothed = nil
                onPose?(nil)
            }
            return
        }

        missingFrames = 0
        let raw = HeadPose(
            yaw: face.yaw?.doubleValue ?? 0,
            pitch: face.pitch?.doubleValue ?? 0,
            roll: face.roll?.doubleValue ?? 0,
            centerX: Double(face.boundingBox.midX),
            centerY: Double(face.boundingBox.midY),
            area: Double(face.boundingBox.width * face.boundingBox.height),
            timestamp: Date()
        )

        smoothed = blend(previous: smoothed, with: raw)
        onPose?(smoothed)
    }

    /// With several people in frame, the largest face is the one at the keyboard.
    private func bestFace(in results: [VNFaceObservation]?) -> VNFaceObservation? {
        results?.max { a, b in
            a.boundingBox.width * a.boundingBox.height < b.boundingBox.width * b.boundingBox.height
        }
    }

    private func blend(previous: HeadPose?, with new: HeadPose) -> HeadPose {
        guard let previous else { return new }
        func mix(_ old: Double, _ fresh: Double) -> Double {
            old + (fresh - old) * smoothing
        }
        return HeadPose(
            yaw: mix(previous.yaw, new.yaw),
            pitch: mix(previous.pitch, new.pitch),
            roll: mix(previous.roll, new.roll),
            centerX: mix(previous.centerX, new.centerX),
            centerY: mix(previous.centerY, new.centerY),
            area: mix(previous.area, new.area),
            timestamp: new.timestamp
        )
    }

    func reset() {
        smoothed = nil
        missingFrames = 0
    }
}
