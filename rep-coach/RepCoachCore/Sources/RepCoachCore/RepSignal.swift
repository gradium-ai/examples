import Foundation

/// What an exercise's signal makes of one frame.
public enum SignalReading: Sendable, Equatable {
    /// How far into the rep the body is: 0 at the rest position, 1 at full depth.
    case progress(Double)
    /// The joints are seen, but the body is not in the exercise at all, e.g. standing under
    /// the pull-up bar with arms down. A rep in flight is abandoned.
    case disengaged
    /// The joints the exercise needs are not seen this frame. Short gaps are tolerated.
    case unseen
}

/// Turns pose frames into a 0…1 rep-progress signal for one exercise.
///
/// Squats, pull-ups and pulldowns are measured as a vertical distance that is largest at rest
/// (hip above knee, wrists above nose or shoulders) and shrinks towards the bottom or top of the
/// rep. The rest distance depends on the person and how far they stand from the phone, so it is
/// learned live by ``RestCalibrator`` rather than assumed. Vertical distances are used instead of
/// joint angles because they survive a straight-on camera: seen from the front, a squatting thigh
/// points at the lens and the hip–knee–ankle angle hardly changes, while the hip's drop towards
/// the knee is plain to see from any side.
///
/// Push-ups are seen side-on, where the elbow angle is well conditioned, so they use it directly.
/// Romanian deadlifts and crunches are a tilt of the torso, measured as the angle of the
/// shoulder–hip line, which needs no calibration and does not change with distance.
public struct RepSignal: Sendable {
    public let exercise: Exercise
    private var smoother = Smoother()
    private var calibrator = RestCalibrator()
    private var smoothedScale = Smoother()
    /// Torso height for Romanian deadlifts seen from the front, where the tilt hardly shows.
    private var torsoSmoother = Smoother()
    private var torsoCalibrator = RestCalibrator()
    private var crunchFloor = FloorCalibrator()
    /// Recent rest-distance readings, to notice someone standing still.
    private var recentGaps: [(time: TimeInterval, gap: Double)] = []
    /// How squarely the body faces the phone, smoothed: see `facingCorrected`.
    private var facingSmoother = Smoother()

    public init(exercise: Exercise) {
        self.exercise = exercise
    }

    /// The learned rest distance, for diagnostics.
    public var restReference: Double? { calibrator.reference }

    /// Depth from the last calibrated frame, uncorrected and not capped at 1, so how deep a rep
    /// went can still be compared once the counting signal saturates (form checks).
    public private(set) var rawDepth: Double?

    public mutating func reset() {
        smoother = Smoother()
        calibrator = RestCalibrator()
        smoothedScale = Smoother()
        torsoSmoother = Smoother()
        torsoCalibrator = RestCalibrator()
        crunchFloor = FloorCalibrator()
        facingSmoother = Smoother()
        recentGaps = []
    }

    /// Reads one frame. `atRest` lets the rest distance adapt; it is held still mid-rep so the
    /// bottom of a rep cannot drag it down.
    public mutating func read(_ frame: PoseFrame, atRest: Bool) -> SignalReading {
        switch exercise {
        case .squat: return squat(frame, atRest: atRest)
        case .pullUp: return pullUp(frame, atRest: atRest)
        case .latPulldown: return latPulldown(frame, atRest: atRest)
        case .pushUp: return pushUp(frame)
        case .armRaise: return armRaise(frame)
        case .lunge: return lunge(frame, atRest: atRest)
        case .romanianDeadlift: return romanianDeadlift(frame, atRest: atRest)
        case .crunch: return crunch(frame, atRest: atRest)
        }
    }

    // MARK: - Exercises

    private mutating func squat(_ f: PoseFrame, atRest: Bool) -> SignalReading {
        // Height of the hip above the knee, averaged over the sides that are seen.
        let gaps = Side.allCases.compactMap { side -> Double? in
            guard let hip = f.point(side.hip), let knee = f.point(side.knee) else { return nil }
            return hip.y - knee.y
        }
        guard !gaps.isEmpty else { return .unseen }
        let gap = smoother.next(gaps.reduce(0, +) / Double(gaps.count))
        return facingCorrected(calibrated(gap, in: f, atRest: atRest), in: f)
    }

    /// Facing a phone at hip height, the knees come towards the lens at the bottom of a squat
    /// and the hips go back, so on screen the knees look lower than they are and the hip–knee gap
    /// stays wider than side-on: a squat just above parallel reads about 0.73 instead of 0.9, a
    /// partial rep. Facing the phone, the deep part of the reading gets up to 0.2 added to make up
    /// for it. Below 0.4 nothing changes, so standing still, stepping about and half squats read
    /// as before. (Measuring the hip's own drop instead would be angle-proof, but it moves just
    /// the same when you step back from the phone.)
    private mutating func facingCorrected(_ reading: SignalReading, in f: PoseFrame) -> SignalReading {
        guard case let .progress(progress) = reading, let ratio = Positioning.facingRatio(f) else { return reading }
        let facing = PoseMath.normalize(facingSmoother.next(ratio), from: 0.2, to: 0.5)
        return .progress(min(1, progress + 0.2 * facing * PoseMath.normalize(progress, from: 0.4, to: 0.75)))
    }

    private mutating func pullUp(_ f: PoseFrame, atRest: Bool) -> SignalReading {
        // Distance of the nose below the hands: arm's length at a dead hang, zero with the chin
        // at the bar.
        guard let nose = f.point(.nose),
              let wristY = f.meanY([.leftWrist, .rightWrist]),
              let shoulderY = f.meanY([.leftShoulder, .rightShoulder])
        else { return .unseen }
        // Hands well below the shoulders: standing under the bar, not hanging from it. At the
        // top of a rep the shoulders come up level with the hands, so allow some margin.
        if wristY < shoulderY - max(0.03, 0.3 * (calibrator.reference ?? 0)) { return .disengaged }
        let gap = smoother.next(wristY - nose.y)
        return calibrated(gap, in: f, atRest: atRest)
    }

    private mutating func latPulldown(_ f: PoseFrame, atRest: Bool) -> SignalReading {
        // Height of the hands above the shoulders: arm's length at the top, about zero with the
        // bar at the upper chest. Works from in front or behind.
        guard let wristY = f.meanY([.leftWrist, .rightWrist]),
              let shoulderY = f.meanY([.leftShoulder, .rightShoulder])
        else { return .unseen }
        let raw = wristY - shoulderY
        // Hands well below the shoulders: the bar has been let go, or this is not a pulldown.
        let floor = -0.35 * (calibrator.reference ?? 0.2)
        if raw < floor { return .disengaged }
        let gap = smoother.next(raw)
        return calibrated(gap, in: f, atRest: atRest)
    }

    private mutating func pushUp(_ f: PoseFrame) -> SignalReading {
        guard let side = f.bestSide({ [$0.shoulder, $0.elbow, $0.wrist] }),
              let elbow = f.angle(side.shoulder, side.elbow, side.wrist)
        else { return .unseen }
        // A push-up is done lying down: the shoulder–hip line within 45° of horizontal.
        if let shoulder = f.point(side.shoulder), let hip = f.point(side.hip) {
            let d = shoulder - hip
            if abs(d.y) > abs(d.x) { return .disengaged }
        }
        let angle = smoother.next(elbow)
        return .progress(PoseMath.normalize(angle, from: 155, to: 95))
    }

    private mutating func armRaise(_ f: PoseFrame) -> SignalReading {
        // Height of the lower hand above the shoulders, in torso lengths: about -0.9 with the
        // arms by the sides, 0 at a T, +0.9 straight overhead. Taking the lower hand means both
        // arms have to go up. Torso lengths make it independent of distance from the phone.
        guard let left = f.point(.leftWrist), let right = f.point(.rightWrist),
              let shoulderY = f.meanY([.leftShoulder, .rightShoulder]),
              let hipY = f.meanY([.leftHip, .rightHip]),
              shoulderY - hipY > 0.02
        else { return .unseen }
        let height = smoother.next((min(left.y, right.y) - shoulderY) / (shoulderY - hipY))
        return .progress(PoseMath.normalize(height, from: -0.7, to: 0.8))
    }

    private mutating func lunge(_ f: PoseFrame, atRest: Bool) -> SignalReading {
        // Height of the hip above the front knee. The squat's signal, but taking the leg whose
        // knee is nearest the hip: at the bottom of a lunge the front thigh is level while the
        // back knee drops towards the floor, so an average would hide the depth.
        let gaps = Side.allCases.compactMap { side -> Double? in
            guard let hip = f.point(side.hip), let knee = f.point(side.knee) else { return nil }
            return hip.y - knee.y
        }
        guard let front = gaps.min() else { return .unseen }
        return calibrated(smoother.next(front), in: f, atRest: atRest)
    }

    private mutating func romanianDeadlift(_ f: PoseFrame, atRest: Bool) -> SignalReading {
        // How far the torso has tipped forward from upright, 0° standing to about 80° at the
        // bottom. Side-on it is the whole story; from an angle the tilt still shows. Straight
        // from the front the torso tips towards the lens, so its height on screen, which shrinks
        // as it tips, is read too and the larger of the two counts.
        guard let side = f.bestSide({ [$0.shoulder, $0.hip] }),
              let shoulder = f.point(side.shoulder), let hip = f.point(side.hip)
        else { return .unseen }
        let d = shoulder - hip
        let tilt = smoother.next(atan2(abs(d.x), d.y) * 180 / .pi)
        var progress = PoseMath.normalize(tilt, from: 15, to: 60)
        if let shoulderY = f.meanY([.leftShoulder, .rightShoulder]), let hipY = f.meanY([.leftHip, .rightHip]) {
            let height = torsoSmoother.next(shoulderY - hipY)
            torsoCalibrator.update(height, at: f.time, frozen: !atRest)
            if let reference = torsoCalibrator.reference, reference > 0 {
                // Tipped by θ, a torso shows cos θ of its height: 50° leaves about 0.64.
                progress = max(progress, PoseMath.normalize(height / reference, from: 0.95, to: 0.6))
            }
        }
        return .progress(progress)
    }

    private mutating func crunch(_ f: PoseFrame, atRest: Bool) -> SignalReading {
        // Lying side-on to the phone: the angle the shoulder–hip line rises off horizontal,
        // measured from its resting angle (a mat, a slope or a tilted phone shift it a little).
        guard let side = f.bestSide({ [$0.shoulder, $0.hip] }),
              let shoulder = f.point(side.shoulder), let hip = f.point(side.hip)
        else { return .unseen }
        let d = shoulder - hip
        // A torso more upright than this is sitting or standing, not doing crunches.
        if abs(d.y) > 2 * abs(d.x) { return .disengaged }
        let lift = smoother.next(atan2(d.y, abs(d.x)) * 180 / .pi)
        crunchFloor.update(lift, at: f.time, frozen: !atRest)
        return .progress(PoseMath.normalize(lift - crunchFloor.floor, from: 0, to: 15))
    }

    private mutating func calibrated(_ gap: Double, in f: PoseFrame, atRest: Bool) -> SignalReading {
        // Each rest distance is roughly a limb or a torso long. Anything far shorter is not a rest
        // position (starting the session crouched at the bottom of a squat, say), and learning it
        // would turn landmark noise into full reps.
        let minimum = 0.4 * (bodyScale(f) ?? 0)
        // Standing still, shallow: that is where this person stands now, even if the reading
        // says otherwise. A rest distance learned while closer to the phone is too long, so
        // standing reads as a quarter-squat, the reading never gets back down to rest and two
        // reps merge into one (seen facing the phone in the gym). Relearn it quickly. Only
        // shallow stillness counts: a pause at the bottom of a rep must not become the rest.
        recentGaps.append((f.time, gap))
        recentGaps.removeAll { f.time - $0.time > 0.8 }
        let still: Bool = {
            guard let first = recentGaps.first, f.time - first.time > 0.6, let reference = calibrator.reference else { return false }
            let gaps = recentGaps.map(\.gap)
            return gaps.max()! - gaps.min()! < 0.06 * reference && 1 - gap / reference < 0.5
        }()
        calibrator.update(gap, at: f.time, frozen: !atRest && !still, minimum: minimum,
                          decayPerSecond: still ? 0.25 : nil)
        guard let reference = calibrator.reference, reference >= minimum else {
            rawDepth = nil
            return .unseen
        }
        rawDepth = 1 - gap / reference
        return .progress(max(0, min(1, 1 - gap / reference)))
    }

    /// The body's size in the frame: the longer of torso length and shoulder width, which between
    /// them survive both front and side views.
    private mutating func bodyScale(_ f: PoseFrame) -> Double? {
        var scale: Double?
        if let shoulderY = f.meanY([.leftShoulder, .rightShoulder]), let hipY = f.meanY([.leftHip, .rightHip]) {
            scale = abs(shoulderY - hipY)
        }
        if let l = f.point(.leftShoulder), let r = f.point(.rightShoulder) {
            scale = max(scale ?? 0, (l - r).length)
        }
        return scale.map { smoothedScale.next($0) }
    }
}

/// Learns the rest distance of a calibrated signal: the largest recent value, following it up at
/// once and letting it sink slowly while at rest, so stepping towards or away from the phone
/// between sets re-calibrates within seconds.
struct RestCalibrator {
    private(set) var reference: Double?
    private var lastTime: TimeInterval?
    /// Fraction of the reference lost per second at rest when the signal stays below it.
    var decayPerSecond = 0.04

    mutating func update(_ value: Double, at time: TimeInterval, frozen: Bool, minimum: Double = 0,
                         decayPerSecond decay: Double? = nil) {
        defer { lastTime = time }
        guard value > 0 else { return }
        guard let ref = reference, ref >= minimum else {
            if value >= minimum { reference = value }
            return
        }
        if frozen {
            reference = max(ref, value)
        } else {
            let dt = min(1, max(0, time - (lastTime ?? time)))
            reference = max(ref * (1 - (decay ?? decayPerSecond) * dt), value)
        }
    }
}

/// Learns a resting angle: the lowest recent value, following it down at once and drifting up
/// slowly while at rest, so lying down a little differently between sets re-calibrates.
struct FloorCalibrator {
    private(set) var floor = 0.0
    private var lastTime: TimeInterval?
    private var started = false
    /// How fast the floor rises at rest when the value stays above it, per second.
    var risePerSecond = 1.0

    init(risePerSecond: Double = 1.0) {
        self.risePerSecond = risePerSecond
    }

    mutating func update(_ value: Double, at time: TimeInterval, frozen: Bool) {
        defer { lastTime = time }
        guard started else {
            floor = value
            started = true
            return
        }
        if frozen {
            floor = min(floor, value)
        } else {
            let dt = min(1, max(0, time - (lastTime ?? time)))
            floor = min(floor + risePerSecond * dt, value)
        }
    }
}

/// A 3-sample median, which removes single-frame landmark jumps, followed by light exponential
/// smoothing. At 15 poses a second this adds about 100 ms of lag.
struct Smoother {
    private var window: [Double] = []
    private var value: Double?
    var alpha = 0.6

    mutating func next(_ sample: Double) -> Double {
        window.append(sample)
        if window.count > 3 { window.removeFirst() }
        let median = window.sorted()[window.count / 2]
        let smoothed = value.map { $0 + alpha * (median - $0) } ?? median
        value = smoothed
        return smoothed
    }
}
