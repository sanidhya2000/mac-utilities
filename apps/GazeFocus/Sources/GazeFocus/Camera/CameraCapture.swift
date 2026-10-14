import Foundation
import AVFoundation
import CoreImage

/// Pulls frames from the camera at a deliberately low rate.
///
/// 720p at 15fps is plenty for head pose and keeps the camera's power draw and
/// CPU cost negligible. Frames are handed straight to the tracker and never
/// retained, copied to disk, or sent anywhere.
final class CameraCapture: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {

    private let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "com.gazefocus.camera", qos: .userInitiated)

    /// Called on a background queue for every frame.
    var onFrame: ((CVPixelBuffer) -> Void)?
    var onError: ((String) -> Void)?

    private(set) var isRunning = false

    /// Target processing rate.
    ///
    /// The camera insists on delivering ~26fps regardless of the format and
    /// duration requested, so this throttle is what actually bounds the cost:
    /// Vision runs only on frames that get through. A head does not change
    /// angle meaningfully between 8 frames a second, and the settle delay is
    /// 300ms anyway, so the lower rate costs nothing in responsiveness.
    private let targetFPS = 8.0
    private var lastDelivered = CFAbsoluteTimeGetCurrent()

    /// Frames the camera produced versus frames passed on, so the probe can
    /// report whether throttling is actually working.
    private(set) var framesReceived = 0
    private(set) var framesDelivered = 0

    static func authorizationStatus() -> AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .video)
    }

    static func requestAccess(_ completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async { completion(granted) }
        }
    }

    static func availableCameras() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
            mediaType: .video, position: .unspecified
        ).devices
    }

    func start(deviceID: String?) {
        guard !isRunning else { return }

        let cameras = Self.availableCameras()
        // A Continuity Camera iPhone can appear and vanish; fall back to any
        // camera rather than failing outright when the chosen one is gone.
        let device = cameras.first { $0.uniqueID == deviceID } ?? cameras.first
        guard let device else {
            onError?("No camera found.")
            return
        }

        session.beginConfiguration()
        // No session preset is set here on purpose. A preset makes
        // AVFoundation own the frame duration and silently override any cap,
        // so the camera kept decoding ~29fps while we discarded most of it.
        // Assigning `activeFormat` below switches the session to input
        // priority by itself, which is what lets the rate cap hold.

        session.inputs.forEach { session.removeInput($0) }
        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else {
                session.commitConfiguration()
                onError?("Camera is unavailable.")
                return
            }
            session.addInput(input)
        } catch {
            session.commitConfiguration()
            onError?("Could not open the camera: \(error.localizedDescription)")
            return
        }

        if !session.outputs.contains(output) {
            output.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            // Dropping late frames keeps latency flat; a stale frame is useless
            // for deciding where someone is looking right now.
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(self, queue: queue)
            if session.canAddOutput(output) { session.addOutput(output) }
        }

        // The format and rate cap must be applied *inside* the configuration
        // block. Done after commit, the session's default `.high` preset wins
        // and the camera keeps decoding at its native rate.
        applyFrameRateCap(to: device)
        session.commitConfiguration()

        queue.async { [weak self] in
            self?.session.startRunning()
        }
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        queue.async { [weak self] in self?.session.stopRunning() }
        isRunning = false
    }

    /// Picks a modest format and caps it at 15fps.
    private func applyFrameRateCap(to device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }

            // Smallest format at least 640 wide that can run at 15fps. Head
            // pose needs a face box and a coarse angle, not detail.
            let suitable = device.formats.filter { format in
                let size = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                guard size.width >= 640, size.width <= 1280 else { return false }
                return format.videoSupportedFrameRateRanges.contains {
                    $0.minFrameRate <= 15 && $0.maxFrameRate >= 15
                }
            }
            let chosenFormat = suitable.min {
                let a = CMVideoFormatDescriptionGetDimensions($0.formatDescription)
                let b = CMVideoFormatDescriptionGetDimensions($1.formatDescription)
                return a.width * a.height < b.width * b.height
            }
            if let chosenFormat { device.activeFormat = chosenFormat }

            guard let range = device.activeFormat.videoSupportedFrameRateRanges.first else { return }

            // Clamp the target into what the device actually supports rather
            // than giving up when it is not bracketed exactly. The previous
            // check silently left capture at the format's native rate — around
            // 26fps here, nearly double the power budget intended.
            let targetSeconds = 1.0 / 15.0
            let shortest = CMTimeGetSeconds(range.minFrameDuration)
            let longest = CMTimeGetSeconds(range.maxFrameDuration)
            let chosen = min(max(targetSeconds, shortest), longest)

            // Pinning both bounds to the same duration locks the frame rate.
            let duration = CMTime(seconds: chosen, preferredTimescale: 600)
            device.activeVideoMinFrameDuration = duration
            device.activeVideoMaxFrameDuration = duration
            Log.info("capture capped at \(String(format: "%.0f", 1 / chosen)) fps")
        } catch {
            Log.info("could not cap frame rate: \(error.localizedDescription)")
        }
    }

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        framesReceived += 1

        // Setting a session preset makes AVFoundation override the device's
        // frame duration, so the hardware cap cannot be relied on. Dropping
        // frames here guarantees the processing rate regardless of what the
        // camera chooses to deliver.
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastDelivered >= 1 / targetFPS - 0.002 else { return }
        lastDelivered = now

        framesDelivered += 1
        onFrame?(pixelBuffer)
    }

    func resetCounters() {
        framesReceived = 0
        framesDelivered = 0
    }
}
