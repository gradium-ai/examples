import CoreMotion
import Foundation
import os
import RepCoachCore

/// The phone's gravity vector, which says how the phone is standing, and the AirPods' head
/// motion. Both go into pose recordings only, never into the count, and run only while a
/// workout screen is open with sensor recording turned on.
///
/// Updates are delivered straight onto the main queue: they are small and at most 25 a second,
/// and the model that consumes them lives there. (Handing each sample from a background queue to
/// the main actor through a new Task overflowed the motion queue's stack on device.)
/// CoreMotion timestamps are seconds since boot, the same clock as camera frame timestamps, so
/// head samples and pose frames line up in a recording.
@MainActor
final class MotionSensors: NSObject {
    enum AirPods: Equatable, Sendable {
        /// This iPhone cannot read headphone motion at all.
        case unavailable
        /// Motion & Fitness access was refused; it can be allowed in Settings.
        case denied
        /// No AirPods with motion sensors are connected.
        case disconnected
        /// Connected, waiting for samples (they stop when the buds are out of the ears).
        case connected
        case streaming

        var label: String {
            switch self {
            case .unavailable: "Head motion unavailable"
            case .denied: "Motion access off"
            case .disconnected: "AirPods not connected"
            case .connected: "AirPods: no motion yet"
            case .streaming: "AirPods motion"
            }
        }
    }

    /// The phone's latest gravity vector in its own axes (x right, y up the screen, z out of the
    /// screen), in g, or nil before the first reading.
    private(set) var gravity: Vec3?
    var onHead: ((HeadMotion) -> Void)?
    var onState: ((AirPods) -> Void)?

    private let phone = CMMotionManager()
    private let headphones = CMHeadphoneMotionManager()
    private let log = Logger(subsystem: "sh.gradium.repcoach", category: "motion")

    func start() {
        if phone.isDeviceMotionAvailable, !phone.isDeviceMotionActive {
            phone.deviceMotionUpdateInterval = 1.0 / 10
            phone.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
                guard let g = motion?.gravity else { return }
                MainActor.assumeIsolated { self?.gravity = Vec3(g.x, g.y, g.z) }
            }
        }

        headphones.delegate = self
        guard headphones.isDeviceMotionAvailable else {
            report(.unavailable)
            return
        }
        switch CMHeadphoneMotionManager.authorizationStatus() {
        case .denied, .restricted:
            report(.denied)
            return
        default:
            break
        }
        report(.disconnected)
        // The first call asks for Motion & Fitness access.
        headphones.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            MainActor.assumeIsolated { self?.received(motion, error) }
        }
    }

    func stop() {
        phone.stopDeviceMotionUpdates()
        headphones.stopDeviceMotionUpdates()
        headphones.delegate = nil
        onHead = nil
        onState = nil
    }

    private func received(_ motion: CMDeviceMotion?, _ error: Error?) {
        if let error {
            log.error("headphone motion: \(error.localizedDescription)")
            if CMHeadphoneMotionManager.authorizationStatus() == .denied { report(.denied) }
            return
        }
        guard let motion else { return }
        let q = motion.attitude.quaternion
        onHead?(HeadMotion(
            time: motion.timestamp,
            attitude: [q.x, q.y, q.z, q.w],
            userAcceleration: Vec3(motion.userAcceleration.x, motion.userAcceleration.y, motion.userAcceleration.z),
            rotationRate: Vec3(motion.rotationRate.x, motion.rotationRate.y, motion.rotationRate.z),
            gravity: Vec3(motion.gravity.x, motion.gravity.y, motion.gravity.z),
            sensor: Self.name(motion.sensorLocation)))
    }

    private func report(_ state: AirPods) {
        log.info("airpods: \(state.label, privacy: .public)")
        onState?(state)
    }

    private static func name(_ location: CMDeviceMotion.SensorLocation) -> String {
        switch location {
        case .headphoneLeft: "left"
        case .headphoneRight: "right"
        default: "default"
        }
    }
}

extension MotionSensors: CMHeadphoneMotionManagerDelegate {
    nonisolated func headphoneMotionManagerDidConnect(_ manager: CMHeadphoneMotionManager) {
        Task { @MainActor in self.report(.connected) }
    }

    nonisolated func headphoneMotionManagerDidDisconnect(_ manager: CMHeadphoneMotionManager) {
        Task { @MainActor in self.report(.disconnected) }
    }
}
