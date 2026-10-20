import AVFoundation
import CoreVideo
import Foundation
import os
import RepCoachCore
import UIKit
import Vision

/// Front camera → Vision body pose → `PoseFrame`s.
///
/// Everything touching the capture session runs on `sessionQueue`, and frames are processed on
/// `videoQueue`, never on the main thread: `startRunning` blocks for a while, and a wedged
/// camera must stall a worker, not the UI. Buffers are rotated to portrait and mirrored to match
/// the preview, so pose coordinates map straight onto the screen.
final class CameraPipeline: NSObject, @unchecked Sendable {
    let session = AVCaptureSession()

    /// Width over height of the frames handed to Vision: 1280×720 turned to portrait.
    static let imageAspect = 720.0 / 1280.0

    /// One processed camera frame: the pose in the image as seen (nil when nobody is found) and,
    /// while rotated passes are on, the poses Vision found in the image turned a quarter turn
    /// each way, keyed "left" and "right".
    struct Output: Sendable {
        var time: TimeInterval
        var pose: PoseFrame?
        var rotated: [String: PoseFrame] = [:]
    }

    typealias PoseHandler = @Sendable (Output) -> Void
    typealias HeartbeatHandler = @Sendable (Heartbeat) -> Void

    /// Set from the main thread, read on the video queue, so behind a lock.
    private let handlers = OSAllocatedUnfairLock<(pose: PoseHandler?, heartbeat: HeartbeatHandler?)>(initialState: (nil, nil))

    /// `onPose` is called on the video queue with each processed frame; `onHeartbeat` about
    /// once a second.
    func setHandlers(onPose: PoseHandler?, onHeartbeat: HeartbeatHandler?) {
        handlers.withLock { $0 = (onPose, onHeartbeat) }
    }

    private var onPose: PoseHandler? { handlers.withLock { $0.pose } }
    private var onHeartbeat: HeartbeatHandler? { handlers.withLock { $0.heartbeat } }

    private let rotatedPasses = OSAllocatedUnfairLock(initialState: false)

    /// Also runs Vision on the image turned a quarter turn each way. A body lying horizontal in
    /// the frame (a push-up filmed side-on) looks upright in one of them, which is what Vision's
    /// pose model is best at. Recorded for comparison; three passes a frame, so 10 a second.
    func setRotatedPasses(_ on: Bool) {
        rotatedPasses.withLock { $0 = on }
    }

    struct Heartbeat: Sendable {
        var cameraFPS: Double
        var poseFPS: Double
        var posesFound: Int
        var thermal: ProcessInfo.ThermalState
    }

    private let sessionQueue = DispatchQueue(label: "repcoach.camera.session")
    private let videoQueue = DispatchQueue(label: "repcoach.camera.video", qos: .userInitiated)
    private let output = AVCaptureVideoDataOutput()
    private let request = VNDetectHumanBodyPoseRequest()
    private let log = Logger(subsystem: "sh.gradium.repcoach", category: "camera")
    private var configured = false

    // Video-queue state.
    private var lastPoseTime: CFTimeInterval = 0
    private var beatStart: CFTimeInterval = CACurrentMediaTime()
    private var framesSinceBeat = 0
    private var posesSinceBeat = 0
    private var foundSinceBeat = 0

    /// Poses per second: 15 is plenty to count reps, and lighter on a warm phone.
    private var poseInterval: CFTimeInterval {
        let hot = ProcessInfo.processInfo.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue
        return hot || rotatedPasses.withLock({ $0 }) ? 1.0 / 10 : 1.0 / 15
    }

    static func requestAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }

    func start() {
        sessionQueue.async { [self] in
            if !configured { configure() }
            if !session.isRunning { session.startRunning() }
            log.info("camera running: \(self.session.isRunning)")
        }
    }

    func stop() {
        sessionQueue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }

    private func configure() {
        configured = true
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        // No microphone: the app speaks but never listens, and must not take over the audio
        // session that plays the voice.
        session.automaticallyConfiguresApplicationAudioSession = false
        session.sessionPreset = .hd1280x720

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input)
        else {
            log.error("no front camera")
            return
        }
        session.addInput(input)
        do {
            try device.lockForConfiguration()
            device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
            device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
            device.unlockForConfiguration()
        } catch {
            log.error("frame rate: \(error.localizedDescription)")
        }

        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
        output.setSampleBufferDelegate(self, queue: videoQueue)
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        if let connection = output.connection(with: .video) {
            if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = true
            }
        }
    }
}

extension CameraPipeline: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = CACurrentMediaTime()
        framesSinceBeat += 1
        defer { heartbeat(now) }
        guard now - lastPoseTime >= poseInterval, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastPoseTime = now
        posesSinceBeat += 1

        // The capture time, on the host clock: the same seconds-since-boot clock CoreMotion
        // stamps phone and AirPods motion with.
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        var out = Output(time: time.isFinite ? time : now)
        out.pose = detect(in: buffer, orientation: .up, time: out.time)
        if rotatedPasses.withLock({ $0 }) {
            out.rotated["left"] = detect(in: buffer, orientation: .left, time: out.time)
            out.rotated["right"] = detect(in: buffer, orientation: .right, time: out.time)
        }
        if out.pose != nil { foundSinceBeat += 1 }
        onPose?(out)
    }

    /// The most confident body Vision finds with the image read in `orientation`, in coordinates
    /// normalized to the image as turned.
    private func detect(in buffer: CVPixelBuffer, orientation: CGImagePropertyOrientation, time: TimeInterval) -> PoseFrame? {
        let width = Double(CVPixelBufferGetWidth(buffer)), height = Double(CVPixelBufferGetHeight(buffer))
        let quarterTurn = orientation == .left || orientation == .right
        let aspect = quarterTurn ? height / width : width / height
        let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: orientation)
        do {
            try handler.perform([request])
        } catch {
            log.error("pose: \(error.localizedDescription)")
            return nil
        }
        guard let observation = request.results?.max(by: { $0.confidence < $1.confidence }),
              let points = try? observation.recognizedPoints(.all)
        else { return nil }
        var joints: [RepCoachCore.Joint: Vec2] = [:]
        var confidence: [RepCoachCore.Joint: Double] = [:]
        for (joint, name) in Self.jointNames {
            guard let p = points[name], p.confidence > 0 else { continue }
            joints[joint] = Vec2(Double(p.location.x), Double(p.location.y))
            confidence[joint] = Double(p.confidence)
        }
        return joints.isEmpty ? nil : PoseFrame(time: time, aspect: aspect, joints: joints, confidence: confidence)
    }

    private func heartbeat(_ now: CFTimeInterval) {
        let elapsed = now - beatStart
        guard elapsed >= 1 else { return }
        let beat = Heartbeat(cameraFPS: Double(framesSinceBeat) / elapsed,
                             poseFPS: Double(posesSinceBeat) / elapsed,
                             posesFound: foundSinceBeat,
                             thermal: ProcessInfo.processInfo.thermalState)
        log.debug("camera \(beat.cameraFPS, format: .fixed(precision: 1)) fps, pose \(beat.poseFPS, format: .fixed(precision: 1)) fps, found \(beat.posesFound)")
        onHeartbeat?(beat)
        beatStart = now
        framesSinceBeat = 0
        posesSinceBeat = 0
        foundSinceBeat = 0
    }

    private static let jointNames: [RepCoachCore.Joint: VNHumanBodyPoseObservation.JointName] = [
        .nose: .nose,
        .leftShoulder: .leftShoulder, .rightShoulder: .rightShoulder,
        .leftElbow: .leftElbow, .rightElbow: .rightElbow,
        .leftWrist: .leftWrist, .rightWrist: .rightWrist,
        .leftHip: .leftHip, .rightHip: .rightHip,
        .leftKnee: .leftKnee, .rightKnee: .rightKnee,
        .leftAnkle: .leftAnkle, .rightAnkle: .rightAnkle,
    ]
}
