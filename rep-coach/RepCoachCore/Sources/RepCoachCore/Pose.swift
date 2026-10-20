import Foundation

/// The body joints RepCoach reasons about, a subset of Vision's body-pose points.
public enum Joint: String, CaseIterable, Codable, Sendable {
    case nose
    case leftShoulder, rightShoulder
    case leftElbow, rightElbow
    case leftWrist, rightWrist
    case leftHip, rightHip
    case leftKnee, rightKnee
    case leftAnkle, rightAnkle
}

public enum Side: CaseIterable, Sendable {
    case left, right

    public var shoulder: Joint { self == .left ? .leftShoulder : .rightShoulder }
    public var elbow: Joint { self == .left ? .leftElbow : .rightElbow }
    public var wrist: Joint { self == .left ? .leftWrist : .rightWrist }
    public var hip: Joint { self == .left ? .leftHip : .rightHip }
    public var knee: Joint { self == .left ? .leftKnee : .rightKnee }
    public var ankle: Joint { self == .left ? .leftAnkle : .rightAnkle }
}

public struct Vec2: Codable, Sendable, Equatable {
    public var x: Double
    public var y: Double

    public init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }

    static func - (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x - b.x, a.y - b.y) }
    var length: Double { (x * x + y * y).squareRoot() }
}

/// One detected body pose, as Vision reports it: joint positions normalized to the upright
/// image (0…1, origin bottom-left, y up) with a confidence each.
///
/// Normalized x and y are in different units on a non-square image (a portrait 720×1280 frame
/// squashes x by 0.56), so angles and lengths must not be computed on them directly. `point(_:)`
/// returns positions scaled by `aspect`, in units of the image height, where they are.
public struct PoseFrame: Sendable, Equatable {
    /// Seconds, from any monotonic clock.
    public var time: TimeInterval
    /// Image width / height of the upright image the joints were found in.
    public var aspect: Double
    public var joints: [Joint: Vec2]
    public var confidence: [Joint: Double]

    /// Joints below this confidence are treated as not seen.
    public static let minimumConfidence = 0.3

    public init(time: TimeInterval, aspect: Double, joints: [Joint: Vec2], confidence: [Joint: Double] = [:]) {
        self.time = time
        self.aspect = aspect
        self.joints = joints
        self.confidence = confidence
    }

    /// The joint in aspect-correct units (x in 0…aspect, y in 0…1, y up), or nil if not seen.
    public func point(_ joint: Joint) -> Vec2? {
        guard let p = joints[joint], (confidence[joint] ?? 1) >= Self.minimumConfidence else { return nil }
        return Vec2(p.x * aspect, p.y)
    }

    public func sees(_ joint: Joint) -> Bool { point(joint) != nil }

    /// Interior angle in degrees at `b`, between `a`–`b`–`c`.
    public func angle(_ a: Joint, _ b: Joint, _ c: Joint) -> Double? {
        guard let pa = point(a), let pb = point(b), let pc = point(c) else { return nil }
        let ba = pa - pb, bc = pc - pb
        let mags = ba.length * bc.length
        guard mags > 0 else { return nil }
        let cosine = max(-1, min(1, (ba.x * bc.x + ba.y * bc.y) / mags))
        return acos(cosine) * 180 / .pi
    }

    /// The mean height of whichever of the joints are seen, or nil if none is.
    func meanY(_ joints: [Joint]) -> Double? {
        let ys = joints.compactMap { point($0)?.y }
        return ys.isEmpty ? nil : ys.reduce(0, +) / Double(ys.count)
    }

    /// The side whose given joints are all seen with the highest mean confidence.
    func bestSide(_ parts: (Side) -> [Joint]) -> Side? {
        Side.allCases
            .filter { side in parts(side).allSatisfy(sees) }
            .max { a, b in
                let ca = parts(a).map { confidence[$0] ?? 1 }.reduce(0, +)
                let cb = parts(b).map { confidence[$0] ?? 1 }.reduce(0, +)
                return ca < cb
            }
    }
}

/// After RepCounterSDK's `PoseMath` (MIT, see THIRD_PARTY_NOTICES.md).
enum PoseMath {
    /// Maps `value` from `[from, to]` onto `[0, 1]`, clamped. `from` may exceed `to`.
    static func normalize(_ value: Double, from: Double, to: Double) -> Double {
        guard from != to else { return 0 }
        return max(0, min(1, (value - from) / (to - from)))
    }
}
