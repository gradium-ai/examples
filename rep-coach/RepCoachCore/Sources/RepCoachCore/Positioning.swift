import Foundation

/// Live directions for getting into position in front of the phone: step back, move left, turn
/// to face the phone, and so on, worked out from what the camera sees. Shown on screen and
/// spoken, so nobody has to walk up to the phone to read it.
///
/// Coordinates are the mirrored camera image, as on screen, so a body near the left edge of the
/// picture is to the person's own left when they face the phone.
public enum Positioning {
    /// What to tell the person, given the latest frame.
    public static func guidance(for exercise: Exercise, frame: PoseFrame?) -> Guidance {
        guard let f = frame else { return Guidance(cue: .stepIntoView) }
        let seen = Joint.allCases.compactMap { joint -> Vec2? in
            guard f.sees(joint) else { return nil }
            return f.joints[joint]
        }
        guard !seen.isEmpty else { return Guidance(cue: .stepIntoView) }
        let minX = seen.map(\.x).min()!, maxX = seen.map(\.x).max()!
        let minY = seen.map(\.y).min()!, maxY = seen.map(\.y).max()!

        // Which edges of the picture the body runs into. The nose is a little below the top of
        // the head, so it counts as cut off a little earlier.
        var edges: Set<PictureEdge> = []
        if minX < edgeMargin { edges.insert(.left) }
        if maxX > 1 - edgeMargin { edges.insert(.right) }
        if maxY > 1 - edgeMargin || (f.joints[.nose].map { f.sees(.nose) && $0.y > 0.93 } ?? false) { edges.insert(.top) }
        if minY < edgeMargin { edges.insert(.bottom) }

        let lying = exercise.stance == .lying
        // Running off one side: move back towards the middle, unless the body is so wide in the
        // picture (lying down close to the phone) that only stepping away will fit it.
        if edges.contains(.left) != edges.contains(.right) {
            if maxX - minX > 0.75 { return Guidance(cue: .stepBack, edges: edges) }
            let towards: ScreenDirection = edges.contains(.left) ? .right : .left
            return Guidance(cue: .move(lateral(towards, in: f, lying: lying)), direction: towards, edges: edges)
        }
        if !edges.isEmpty { return Guidance(cue: .stepBack, edges: edges) }

        if let part = exercise.requiredParts.first(where: { !$0.isSeen(in: f) }) {
            return Guidance(cue: .cantSee(part))
        }

        if lying, let tilt = torsoTilt(f), tilt > 45 {
            return Guidance(cue: .lieDown)
        }
        if exercise.needsWholeBody {
            // Too small in the picture and the landmarks get noisy.
            let size = lying ? maxX - minX : maxY - minY
            if size < (lying ? 0.3 : 0.35) { return Guidance(cue: .comeCloser) }
        }
        if let cue = exercise.turn(f) { return Guidance(cue: cue) }
        return Guidance(cue: .ready)
    }

    /// Shoulder width over torso length, both as seen: about 0.65 facing the phone, 0.45–0.6 at
    /// an angle, under 0.15 side-on (measured on real footage). Facing straight on and at an
    /// angle overlap, so only side-on is told apart reliably.
    public static func facingRatio(_ f: PoseFrame) -> Double? {
        guard let ls = f.point(.leftShoulder), let rs = f.point(.rightShoulder),
              let lh = f.point(.leftHip), let rh = f.point(.rightHip)
        else { return nil }
        let shoulders = Vec2((ls.x + rs.x) / 2, (ls.y + rs.y) / 2)
        let hips = Vec2((lh.x + rh.x) / 2, (lh.y + rh.y) / 2)
        let torso = (shoulders - hips).length
        guard torso > 0.02 else { return nil }
        return abs(ls.x - rs.x) / torso
    }

    /// Fraction of the picture's width or height treated as its edge.
    static let edgeMargin = 0.03

    /// Degrees of the shoulder–hip line from horizontal.
    private static func torsoTilt(_ f: PoseFrame) -> Double? {
        guard let side = f.bestSide({ [$0.shoulder, $0.hip] }),
              let s = f.point(side.shoulder), let h = f.point(side.hip)
        else { return nil }
        let d = s - h
        return atan2(abs(d.y), abs(d.x)) * 180 / .pi
    }

    /// Puts a sideways move on screen into words the person can follow without looking.
    private static func lateral(_ towards: ScreenDirection, in f: PoseFrame, lying: Bool) -> Cue.Lateral {
        let shoulders = Side.allCases.compactMap { f.point($0.shoulder) }
        let hips = Side.allCases.compactMap { f.point($0.hip) }
        if lying {
            // Along the body: towards the head or the feet.
            guard let s = shoulders.first, let h = hips.first else { return .toMiddle }
            let headOnRight = s.x > h.x
            return (towards == .right) == headOnRight ? .towardsHead : .towardsFeet
        }
        if let ratio = facingRatio(f), ratio >= 0.25 {
            // Facing the phone, the mirrored picture's right is the person's right.
            return towards == .right ? .yourRight : .yourLeft
        }
        // Side-on: forwards or backwards, by which way the face points.
        guard let nose = f.point(.nose), !shoulders.isEmpty else { return .toMiddle }
        let shoulderX = shoulders.map(\.x).reduce(0, +) / Double(shoulders.count)
        let facingRight = nose.x > shoulderX
        return (towards == .right) == facingRight ? .forwards : .backwards
    }
}

/// Steadies the directions: a new one only shows once it has held for `hold` seconds, so a
/// joint flickering in and out of view does not flip the instruction every frame.
public struct GuidanceFilter: Sendable {
    public private(set) var shown: Guidance?
    /// When the shown cue was first seen, in the frames' clock.
    public private(set) var shownSince: TimeInterval = 0
    private var candidate: Guidance?
    private var candidateSince: TimeInterval = 0
    public var hold: TimeInterval

    public init(hold: TimeInterval = 0.5) {
        self.hold = hold
    }

    public mutating func update(_ guidance: Guidance, at time: TimeInterval) -> Guidance? {
        if guidance.cue == shown?.cue {
            shown = guidance      // the same instruction; keep its arrow and edges current
            candidate = nil
            return shown
        }
        if guidance.cue != candidate?.cue {
            candidate = guidance
            candidateSince = time
        }
        if shown == nil || time - candidateSince >= hold {
            shown = guidance
            shownSince = candidateSince
            candidate = nil
        }
        return shown
    }

    /// How long the shown cue has held.
    public func held(at time: TimeInterval) -> TimeInterval { shown == nil ? 0 : time - shownSince }

    public mutating func reset() {
        self = GuidanceFilter(hold: hold)
    }
}

public enum ScreenDirection: Sendable { case left, right }
public enum PictureEdge: Sendable { case top, bottom, left, right }

public struct Guidance: Equatable, Sendable {
    public var cue: Cue
    /// Which way to move on screen, for an arrow.
    public var direction: ScreenDirection?
    /// The edges of the picture the body runs off.
    public var edges: Set<PictureEdge> = []

    public init(cue: Cue, direction: ScreenDirection? = nil, edges: Set<PictureEdge> = []) {
        self.cue = cue
        self.direction = direction
        self.edges = edges
    }
}

/// One instruction, short enough to say while someone is walking into place.
public enum Cue: Hashable, Sendable {
    case stepIntoView
    case stepBack
    case comeCloser
    case move(Lateral)
    case faceThePhone
    case turnSideways
    case lieDown
    case cantSee(BodyPart)
    case ready

    public enum Lateral: Hashable, Sendable, CaseIterable {
        case yourLeft, yourRight, forwards, backwards, towardsHead, towardsFeet, toMiddle
    }

    public var text: String {
        switch self {
        case .stepIntoView: "Step into view."
        case .stepBack: "Step back from the phone."
        case .comeCloser: "Come a little closer."
        case .move(.yourLeft): "Move a step to your left."
        case .move(.yourRight): "Move a step to your right."
        case .move(.forwards): "Take a step forwards."
        case .move(.backwards): "Take a step backwards."
        case .move(.towardsHead): "Shift towards your head."
        case .move(.towardsFeet): "Shift towards your feet."
        case .move(.toMiddle): "Move to the middle of the picture."
        case .faceThePhone: "Turn to face the phone."
        case .turnSideways: "Turn sideways, your shoulder to the phone."
        case .lieDown: "Lie down, side-on to the phone."
        case let .cantSee(part): "I can't see your \(part.name)."
        case .ready: "Hold still."
        }
    }

    /// Every cue, so each can be synthesized ahead of time.
    public static var all: [Cue] {
        [.stepIntoView, .stepBack, .comeCloser, .faceThePhone, .turnSideways, .lieDown, .ready]
            + Lateral.allCases.map(Cue.move) + BodyPart.allCases.map(Cue.cantSee)
    }
}

/// A body part the camera has to see, on at least one side (`bothHands`: on both).
public enum BodyPart: String, Hashable, Sendable, CaseIterable {
    case face, shoulders, arm, hands, bothHands, hips, knees

    public var name: String {
        switch self {
        case .face: "face"
        case .shoulders: "shoulders"
        case .arm: "arm"
        case .hands, .bothHands: "hands"
        case .hips: "hips"
        case .knees: "knees"
        }
    }

    /// What usually brings the part back into view.
    var hint: String? {
        switch self {
        case .hands, .bothHands: "tilt the phone up"
        case .arm: "turn side-on"
        case .hips, .knees: "move the phone back"
        case .face, .shoulders: nil
        }
    }

    func isSeen(in f: PoseFrame) -> Bool {
        switch self {
        case .face: f.sees(.nose)
        case .shoulders: Side.allCases.contains { f.sees($0.shoulder) }
        case .arm: Side.allCases.contains { [$0.shoulder, $0.elbow, $0.wrist].allSatisfy(f.sees) }
        case .hands: Side.allCases.contains { f.sees($0.wrist) }
        case .bothHands: Side.allCases.allSatisfy { f.sees($0.wrist) }
        case .hips: Side.allCases.contains { f.sees($0.hip) }
        case .knees: Side.allCases.contains { f.sees($0.knee) }
        }
    }
}

public enum Stance: Sendable {
    /// Any angle to the phone works.
    case standing
    /// The exercise is read from the front: side-on hides an arm.
    case facingPhone
    /// Side-on, shoulder to the phone: facing it, a lunge hardly shows (recorded 2026-10-15:
    /// depth 0.15–0.25 facing the phone, full depth side-on).
    case sideways
    /// On the floor, side-on to the phone.
    case lying
}

public extension Exercise {
    var stance: Stance {
        switch self {
        case .pullUp, .latPulldown, .armRaise: .facingPhone
        case .pushUp, .crunch: .lying
        case .lunge: .sideways
        case .squat, .romanianDeadlift: .standing
        }
    }

    /// What the camera must see, most important first.
    var requiredParts: [BodyPart] {
        switch self {
        case .squat, .lunge: [.shoulders, .hips, .knees]
        case .pullUp: [.face, .hands, .shoulders]
        case .latPulldown: [.hands, .shoulders]
        case .pushUp: [.arm, .hips]
        case .armRaise: [.shoulders, .hips, .bothHands]
        case .romanianDeadlift, .crunch: [.shoulders, .hips]
        }
    }

    /// What is wrong with the picture mid-workout, in a few words for the screen: the first
    /// required part that is not seen, or the way to turn.
    func framingProblem(_ frame: PoseFrame?) -> String? {
        guard let f = frame else { return "Step into view" }
        if let part = requiredParts.first(where: { !$0.isSeen(in: f) }) {
            return "Can't see your \(part.name)" + (part.hint.map { ": \($0)" } ?? "")
        }
        return turn(f).map { String($0.text.dropLast()) }
    }

    /// Which way to turn, if the body faces the phone the wrong way for this exercise. Shoulder
    /// width over torso length is about 0.6 facing the phone and under 0.15 side-on in the gym
    /// recordings; between them is an angle, which counts as wrong for both.
    func turn(_ f: PoseFrame) -> Cue? {
        guard let ratio = Positioning.facingRatio(f) else { return nil }
        switch stance {
        case .facingPhone: return ratio < 0.25 ? .faceThePhone : nil
        case .sideways: return ratio > 0.35 ? .turnSideways : nil
        case .standing, .lying: return nil
        }
    }

    /// Whether the whole body has to be in the picture, so standing too far away matters.
    internal var needsWholeBody: Bool {
        switch self {
        case .squat, .lunge, .romanianDeadlift, .pushUp, .crunch: true
        case .pullUp, .latPulldown, .armRaise: false
        }
    }
}
