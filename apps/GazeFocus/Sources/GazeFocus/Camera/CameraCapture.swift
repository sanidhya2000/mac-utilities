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
        session.sessionPreset = .hd1280x720

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

        session.commitConfiguration()
        applyFrameRateCap(to: device)

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

    /// Caps capture at 15fps where the device allows it.
    private func applyFrameRateCap(to device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }

            let target = CMTime(value: 1, timescale: 15)
            let ranges = device.activeFormat.videoSupportedFrameRateRanges
            if let range = ranges.first, range.minFrameDuration <= target,
               target <= range.maxFrameDuration {
                device.activeVideoMinFrameDuration = target
                device.activeVideoMaxFrameDuration = target
            }
        } catch {
            Log.info("could not cap frame rate: \(error.localizedDescription)")
        }
    }

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        onFrame?(pixelBuffer)
    }
}
