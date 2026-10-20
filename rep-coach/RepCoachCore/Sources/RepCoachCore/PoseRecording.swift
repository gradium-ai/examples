import Foundation

public struct Vec3: Codable, Sendable, Equatable {
    public var x: Double
    public var y: Double
    public var z: Double

    public init(_ x: Double, _ y: Double, _ z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }
}

/// One AirPods head-motion sample, from `CMHeadphoneMotionManager`.
public struct HeadMotion: Sendable, Equatable {
    /// Seconds, on the same clock as pose frames.
    public var time: TimeInterval
    /// Head attitude as a quaternion (x, y, z, w).
    public var attitude: [Double]
    /// Acceleration the user gives the head, gravity removed, in g.
    public var userAcceleration: Vec3
    /// Radians per second.
    public var rotationRate: Vec3
    /// Gravity in the headphones' frame, in g.
    public var gravity: Vec3
    /// Which bud the sample came from: "left", "right" or "default".
    public var sensor: String

    public init(time: TimeInterval, attitude: [Double], userAcceleration: Vec3, rotationRate: Vec3, gravity: Vec3, sensor: String) {
        self.time = time
        self.attitude = attitude
        self.userAcceleration = userAcceleration
        self.rotationRate = rotationRate
        self.gravity = gravity
        self.sensor = sensor
    }
}

/// Sensor recordings: a JSON-lines file of everything the counter could use from a session, so
/// thresholds can be tuned and bugs reproduced off the phone with `repcoach-replay`. Joints and
/// motion only, never video.
///
/// The first line is a ``Header``. Each later line is either a pose frame,
/// `{"t":12.34,"j":{"nose":[x,y,confidence],...},"g":[x,y,z],"rot":{"left":{...}}}`, with raw
/// Vision coordinates, the phone's gravity vector and optionally the poses Vision found in the
/// image rotated a quarter turn each way; or an AirPods sample, `{"t":12.35,"h":{...}}`.
/// Version 1 files (pose only) read the same way.
public enum PoseRecording {
    public struct Header: Codable, Sendable {
        public var exercise: Exercise
        public var aspect: Double
        public var recordedAt: Date
        public var note: String?
        /// 2 adds gravity, rotated poses and head motion. Absent in version 1 files.
        public var version: Int?

        public init(exercise: Exercise, aspect: Double, recordedAt: Date = Date(), note: String? = nil, version: Int? = 2) {
            self.exercise = exercise
            self.aspect = aspect
            self.recordedAt = recordedAt
            self.note = note
            self.version = version
        }
    }

    /// What else was known when a pose frame was taken.
    public struct Extras: Sendable, Equatable {
        /// The phone's gravity vector in its own axes (x right, y up the screen, z out of it), in g.
        public var gravity: Vec3?
        /// Poses found in the image rotated a quarter turn, keyed by the Vision orientation used
        /// ("left", "right"). Coordinates are normalized to that rotated image, `aspect` is its
        /// width over height.
        public var rotated: [String: PoseFrame]

        public init(gravity: Vec3? = nil, rotated: [String: PoseFrame] = [:]) {
            self.gravity = gravity
            self.rotated = rotated
        }
    }

    public enum Entry: Sendable, Equatable {
        case frame(PoseFrame, Extras)
        case head(HeadMotion)
    }

    private struct JointsLine: Codable {
        var a: Double?
        var j: [String: [Double]]
    }

    private struct HeadLine: Codable {
        var q: [Double]
        var ua: [Double]
        var rr: [Double]
        var g: [Double]
        var s: String
    }

    private struct Line: Codable {
        var t: TimeInterval
        var j: [String: [Double]]?
        var g: [Double]?
        var rot: [String: JointsLine]?
        var h: HeadLine?
    }

    public static func encode(_ header: Header) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(header) + Data([0x0A])
    }

    public static func encode(_ frame: PoseFrame, extras: Extras = Extras()) throws -> Data {
        let rotated = extras.rotated.mapValues { JointsLine(a: round4($0.aspect), j: joints($0)) }
        let line = Line(t: round4(frame.time), j: joints(frame), g: extras.gravity.map(array),
                        rot: rotated.isEmpty ? nil : rotated)
        return try JSONEncoder().encode(line) + Data([0x0A])
    }

    public static func encode(_ head: HeadMotion) throws -> Data {
        let line = Line(t: round4(head.time), h: HeadLine(
            q: head.attitude.map(round4), ua: array(head.userAcceleration), rr: array(head.rotationRate),
            g: array(head.gravity), s: head.sensor))
        return try JSONEncoder().encode(line) + Data([0x0A])
    }

    /// The header and pose frames only, which is all the counter takes.
    public static func decode(_ data: Data) throws -> (Header, [PoseFrame]) {
        let (header, entries) = try decodeEntries(data)
        let frames = entries.compactMap { entry -> PoseFrame? in
            if case let .frame(frame, _) = entry { frame } else { nil }
        }
        return (header, frames)
    }

    public static func decodeEntries(_ data: Data) throws -> (Header, [Entry]) {
        let lines = data.split(separator: 0x0A).filter { !$0.isEmpty }
        guard let first = lines.first else { throw CocoaError(.fileReadCorruptFile) }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let header = try decoder.decode(Header.self, from: Data(first))
        let entries = try lines.dropFirst().map { raw -> Entry in
            let line = try decoder.decode(Line.self, from: Data(raw))
            if let h = line.h {
                return .head(HeadMotion(time: line.t, attitude: h.q, userAcceleration: vec3(h.ua),
                                        rotationRate: vec3(h.rr), gravity: vec3(h.g), sensor: h.s))
            }
            let frame = pose(line.t, header.aspect, line.j ?? [:])
            var rotated: [String: PoseFrame] = [:]
            for (key, value) in line.rot ?? [:] {
                rotated[key] = pose(line.t, value.a ?? 1 / header.aspect, value.j)
            }
            return .frame(frame, Extras(gravity: line.g.map(vec3), rotated: rotated))
        }
        return (header, entries)
    }

    private static func joints(_ frame: PoseFrame) -> [String: [Double]] {
        var joints: [String: [Double]] = [:]
        for (joint, p) in frame.joints {
            joints[joint.rawValue] = [round4(p.x), round4(p.y), round4(frame.confidence[joint] ?? 1)]
        }
        return joints
    }

    private static func pose(_ time: TimeInterval, _ aspect: Double, _ raw: [String: [Double]]) -> PoseFrame {
        var joints: [Joint: Vec2] = [:]
        var confidence: [Joint: Double] = [:]
        for (name, v) in raw {
            guard let joint = Joint(rawValue: name), v.count == 3 else { continue }
            joints[joint] = Vec2(v[0], v[1])
            confidence[joint] = v[2]
        }
        return PoseFrame(time: time, aspect: aspect, joints: joints, confidence: confidence)
    }

    private static func array(_ v: Vec3) -> [Double] { [round4(v.x), round4(v.y), round4(v.z)] }
    private static func vec3(_ a: [Double]) -> Vec3 { a.count == 3 ? Vec3(a[0], a[1], a[2]) : Vec3(0, 0, 0) }
    private static func round4(_ v: Double) -> Double { (v * 10_000).rounded() / 10_000 }
}

/// Runs frames through the signal, counter and set tracker exactly as the app does, without
/// the camera or the voice. Used by the replay tool and the checks.
public struct RepPipeline: Sendable {
    public private(set) var signal: RepSignal
    public private(set) var counter: RepCounter
    public private(set) var tracker: SessionTracker
    public private(set) var form: FormCheck
    /// Form faults of the set that `finish` closed.
    public private(set) var lastSetForm: [FormFault] = []

    public enum Output: Sendable, Equatable {
        case rep(set: Int, number: Int, duration: TimeInterval)
        case partial(depth: Double)
        case setEnd(SetEnd)
        /// Form faults in the rep just counted, and those to say out loud now (each once).
        case form(faults: Set<FormFault>, say: [FormFault])
    }

    public init(exercise: Exercise, restTimeout: TimeInterval = 10, startTime: TimeInterval = 0) {
        signal = RepSignal(exercise: exercise)
        counter = RepCounter(exercise: exercise)
        tracker = SessionTracker(exercise: exercise, restTimeout: restTimeout, startTime: startTime)
        form = FormCheck(exercise: exercise)
    }

    public mutating func process(_ frame: PoseFrame) -> [Output] {
        var out: [Output] = []
        if let end = tracker.tick(at: frame.time) { out.append(.setEnd(withForm(end))) }
        let reading = signal.read(frame, atRest: counter.isAtRest)
        let wasInRep = !counter.isAtRest
        let event = counter.update(reading, at: frame.time)
        form.observe(frame, progress: counter.lastProgress, depth: signal.rawDepth, inRep: wasInRep || !counter.isAtRest)
        switch event {
        case let .rep(duration):
            let set = tracker.setNumber
            out.append(.rep(set: set, number: tracker.rep(at: frame.time), duration: duration))
            let (faults, say) = form.repCounted()
            if !faults.isEmpty { out.append(.form(faults: faults, say: say)) }
        case let .partial(depth):
            tracker.activity(at: frame.time)
            let (faults, say) = form.repPartial()
            out.append(.partial(depth: depth))
            if !faults.isEmpty { out.append(.form(faults: faults, say: say)) }
        case nil:
            if !counter.isAtRest { tracker.activity(at: frame.time) }
        }
        // A quarter squat the counter ignored: a short rep within a set, and its posture counts.
        if let shallow = form.takeShallowRep() {
            if tracker.isInSet {
                tracker.activity(at: frame.time)
                out.append(.partial(depth: shallow.depth))
            }
            if !shallow.faults.isEmpty { out.append(.form(faults: shallow.faults, say: shallow.say)) }
        }
        return out
    }

    /// A frame in which nobody was found. A rep in flight is abandoned if the body stays out
    /// of view, so stepping away mid-rep and coming back upright does not count.
    public mutating func missing(at time: TimeInterval) -> [Output] {
        _ = counter.update(.unseen, at: time)
        return tick(at: time).map { [.setEnd($0)] } ?? []
    }

    /// Advances the clock without a frame, so a set can close while nobody is in view.
    public mutating func tick(at time: TimeInterval) -> SetEnd? {
        tracker.tick(at: time).map { withForm($0) }
    }

    public mutating func finish(at time: TimeInterval) -> WorkoutSummary {
        let open = tracker.repsInSet
        lastSetForm = form.setFinished()
        if open < tracker.minimumSetReps { lastSetForm = [] }
        return tracker.finish(at: time)
    }

    private mutating func withForm(_ end: SetEnd) -> SetEnd {
        var end = end
        let faults = form.setFinished()
        end.form = end.discarded ? [] : faults
        return end
    }
}
