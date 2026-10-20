import Foundation
import os
import RepCoachCore

/// Writes a session's sensor data to `Documents/Recordings`, for `repcoach-replay` on a Mac:
/// pose frames (with the phone's gravity and, for push-ups, the rotated-image poses) and AirPods
/// head motion, in the order they arrive. The folder shows up in Finder (the phone's Files tab)
/// and in the Files app. Never images, and only when the user turns recording on.
final class PoseRecorder {
    let url: URL
    private let handle: FileHandle
    private var failed = false
    private(set) var frames = 0
    private(set) var headSamples = 0
    private let log = Logger(subsystem: "sh.gradium.repcoach", category: "recorder")

    init?(exercise: Exercise, aspect: Double) {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appending(path: "Recordings")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        url = dir.appending(path: "\(formatter.string(from: Date()))-\(exercise.rawValue).jsonl")
        // Encrypted while the phone is locked, but an open file can keep being written if the
        // screen locks mid-set.
        guard FileManager.default.createFile(atPath: url.path, contents: nil,
                                             attributes: [.protectionKey: FileProtectionType.completeUnlessOpen]),
              let handle = try? FileHandle(forWritingTo: url)
        else { return nil }
        self.handle = handle
        write { try PoseRecording.encode(PoseRecording.Header(exercise: exercise, aspect: aspect)) }
    }

    func write(_ frame: PoseFrame, extras: PoseRecording.Extras) {
        frames += 1
        write { try PoseRecording.encode(frame, extras: extras) }
    }

    func write(_ head: HeadMotion) {
        headSamples += 1
        write { try PoseRecording.encode(head) }
    }

    private func write(_ line: () throws -> Data) {
        guard !failed else { return }
        do {
            try handle.write(contentsOf: line())
        } catch {
            // A full disk must not end the workout: stop recording, keep counting.
            failed = true
            log.error("recording stopped: \(error.localizedDescription)")
        }
    }

    func close() {
        try? handle.close()
        log.info("recording saved: \(self.url.lastPathComponent, privacy: .public), \(self.frames) frames, \(self.headSamples) head samples")
    }
}
