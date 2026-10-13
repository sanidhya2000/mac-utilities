import Foundation
import Vision
import CoreVideo
import GazeCore

/// Runs Vision's face-landmark request over camera frames and smooths the
/// result. Everything stays on-device; Vision never touches the network.
final class HeadPoseTracker {


    /// Exponential smoothing factor. Low enough to kill per-frame jitter,
    /// high enough that a real head turn still lands within ~100ms.
    private let smoothing = 0.35
    private var smoothed: HeadPose?

    /// When a face was last seen. Used to stop acting on a stale pose once
    /// the user has actually walked away.
    private var lastSeenFace = Date.distantPast
    private(set) var missingFrames = 0

    /// How long a pose stays usable after detection drops out.
    ///
    /// Detection is far from continuous in practice: at a desk, with the camera
    /// below the monitor being looked at, a face is resolvable in only a
    /// fraction of frames. Counting consecutive misses made tracking flap
    /// between "tracking" and "can't see you" constantly; a time budget rides
    /// over the gaps while still noticing a genuine departure.
    private let poseGraceSeconds: TimeInterval = 1.8

    var onPose: ((HeadPose?) -> Void)?

    func process(_ pixelBuffer: CVPixelBuffer) {
        let request = VNDetectFaceRectanglesRequest()
        // Revision 3 reports pitch as well as yaw and roll.
        request.revision = VNDetectFaceRectanglesRequestRevision3

        // A stateless per-image handler, not VNSequenceRequestHandler.
        // The sequence handler carries tracking state between frames and
        // assumes they are contiguous; once frames are dropped to hold the
        // processing rate down, its detection rate collapses — measured at
        // roughly 5% versus 98% here. Face rectangles need no such state.
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                            orientation: .leftMirrored,
                                            options: [:])
        do {
            try handler.perform([request])
        } catch {
            Log.error("vision request failed: \(error.localizedDescription)")
            return
        }

        guard let face = bestFace(in: request.results) else {
            missingFrames += 1
            // Keep reporting the last known pose until the grace period runs
            // out, so an intermittent detection does not look like absence.
            if Date().timeIntervalSince(lastSeenFace) > poseGraceSeconds {
                smoothed = nil
                onPose?(nil)
            } else if let smoothed {
                onPose?(smoothed)
            }
            return
        }

        missingFrames = 0
        lastSeenFace = Date()
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
        lastSeenFace = .distantPast
    }
}
