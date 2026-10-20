import Foundation

/// A form fault the camera can see reliably, each grounded in published coaching guidance and
/// only judged from a view that shows it: knees caving in shows from the front, not the side;
/// forward lean shows from the side, not the front. What the camera cannot see (a rounding
/// back: Vision has no points along the spine) is never judged.
///
/// Sources:
/// - Squat: knees track over the toes and thighs reach parallel (NSCA squat technique);
///   "knees move inward" and "excessive forward lean" are compensations in NASM's overhead
///   squat assessment, which aims for the trunk parallel to the shin.
/// - Romanian deadlift: "the knees remain slightly flexed as the hips move backward" (NSCA,
///   Kinetic Select: Romanian Deadlift).
/// - Lunge: lower until the front thigh is about parallel to the floor (ACE exercise library).
/// - Push-up: "a straight line from head to heel" (NASM exercise library); no sagging or
///   piked hips (Catalyst Athletics).
/// - Pull-up: chin to the bar, then down until the arms are fully extended (NAPFA and FBI
///   pull-up test standards).
public enum FormFault: String, CaseIterable, Sendable {
    case shallow
    case fadingDepth
    case kneesCaveIn
    case forwardLean
    case kneesTooBent
    case hipsSag
    case hipsPike
    case armsBent

    /// Said once per workout, the first time the fault shows on two of three reps. Depth is
    /// not called out mid-set: a rep that falls short already shows "Go all the way".
    public var live: String? {
        switch self {
        case .shallow, .fadingDepth: nil
        case .kneesCaveIn: "Push your knees out."
        case .forwardLean: "Chest up."
        case .kneesTooBent: "Hips back, knees soft."
        case .hipsSag: "Hips up."
        case .hipsPike: "Hips down."
        case .armsBent: "Straighten your arms at the bottom."
        }
    }

    /// Shown on screen in red while the rep with the fault is fresh.
    public var label: String {
        switch self {
        case .shallow: "Not deep enough"
        case .fadingDepth: "Getting shallower"
        case .kneesCaveIn: "Knees caving in"
        case .forwardLean: "Leaning forward"
        case .kneesTooBent: "Knees too bent"
        case .hipsSag: "Hips sagging"
        case .hipsPike: "Hips too high"
        case .armsBent: "Arms not straight"
        }
    }

    /// After the set: one short sentence saying what to do.
    public func advice(for exercise: Exercise) -> String {
        switch self {
        case .shallow:
            switch exercise {
            case .squat: "Squat a bit deeper, thighs level with the floor."
            case .lunge: "Lunge a bit deeper, front thigh level with the floor."
            case .pushUp: "Lower your chest closer to the floor."
            case .pullUp: "Pull until your chin reaches the bar."
            case .latPulldown: "Pull the bar down to your upper chest."
            case .romanianDeadlift: "Push your hips back a little further."
            case .crunch: "Curl up a little higher, shoulder blades off the floor."
            case .armRaise: "Raise your arms all the way overhead."
            }
        case .fadingDepth:
            exercise == .pushUp ? "Go all the way down on your last reps too." : "You can go deeper on your last reps."
        case .kneesCaveIn: "Keep your knees in line with your toes."
        case .forwardLean: "Keep your chest up as you go down."
        case .kneesTooBent: "Bend your knees only a little and push your hips back."
        case .hipsSag: "Keep your body straight, don't let your hips sag."
        case .hipsPike: "Lower your hips into a straight line from head to heels."
        case .armsBent: "Lower all the way until your arms are straight."
        }
    }

    /// The bones drawn in red for the fault.
    public var bones: [(Joint, Joint)] {
        switch self {
        case .shallow, .fadingDepth: []
        case .kneesCaveIn: [(.leftKnee, .leftAnkle), (.rightKnee, .rightAnkle), (.leftHip, .leftKnee), (.rightHip, .rightKnee)]
        case .forwardLean, .hipsSag, .hipsPike: [(.leftShoulder, .leftHip), (.rightShoulder, .rightHip), (.leftHip, .leftKnee), (.rightHip, .rightKnee)]
        case .kneesTooBent: [(.leftHip, .leftKnee), (.rightHip, .rightKnee), (.leftKnee, .leftAnkle), (.rightKnee, .rightAnkle)]
        case .armsBent: [(.leftShoulder, .leftElbow), (.rightShoulder, .rightElbow), (.leftElbow, .leftWrist), (.rightElbow, .rightWrist)]
        }
    }

    /// Advice sentences an exercise can give, so each can be synthesized ahead of time.
    public static func phrases(for exercise: Exercise) -> [String] {
        allCases.map { $0.advice(for: exercise) } + allCases.compactMap(\.live)
    }

    /// Every advice, live and praise sentence, repeats included.
    public static var allPhrases: [String] {
        Exercise.allCases.flatMap(phrases(for:)) + Exercise.allCases.map(FormCheck.praise)
    }
}

/// Watches the reps of a set for form faults: the deepest frame of each rep is measured, and
/// the rest between reps for what happens at the top.
public struct FormCheck: Sendable {
    public let exercise: Exercise

    /// Faults per counted rep in this set, in order.
    public private(set) var reps: [Set<FormFault>] = []
    /// Depth reached by each counted rep in this set.
    private var depths: [Double] = []
    private var partials = 0
    /// The bottom of the rep under way: its frame, and how deep by `bottomness`.
    private var deepest: (depth: Double, frame: PoseFrame)?
    /// The deepest raw depth of the rep under way (see `RepSignal.rawDepth`).
    private var maxDepth: Double?
    /// The deepest counting progress of the rep under way.
    private var maxProgress: Double?
    /// Frames of the movement under way with the knees caving in (see `kneesCaveIn`).
    private var caveFrames = 0
    /// Knee spread over ankle spread while standing, facing the phone (see `kneesCaveIn`).
    private var standingKneeRatio: Double?
    /// The straightest the elbows got while resting since the last rep (pull-ups).
    private var restElbow: Double?
    /// Faults already spoken this workout.
    private var spoken: Set<FormFault> = []
    /// Faults of every attempt in this set: counted reps, partial reps and shallow dips.
    private var attempts: [Set<FormFault>] = []
    /// A dip under way that may never get deep enough for the counter (a quarter squat).
    private var dip: Dip?
    private var shallow: ShallowRep?

    private struct Dip {
        var start: TimeInterval
        var peak: Double
        var bottom: (depth: Double, frame: PoseFrame)?
        var ankles: [Vec2]?
        /// How far the feet moved, in torso lengths: a planted squat barely moves them.
        var drift = 0.0
        var handled = false
    }

    /// A dip that started a squat but never reached the counter's start (0.4): too shallow to be
    /// a rep, yet a squat attempt whose posture counts, and a short rep within a set.
    public struct ShallowRep: Sendable {
        public let depth: Double
        public let faults: Set<FormFault>
        public let say: [FormFault]
    }

    public init(exercise: Exercise) {
        self.exercise = exercise
    }

    /// Feed every frame with its rep progress; `inRep` is whether a rep is under way.
    public mutating func observe(_ frame: PoseFrame, progress: Double?, depth: Double? = nil, inRep: Bool) {
        watchDips(frame, progress: progress, depth: depth)
        let upright = (progress ?? 1) <= 0.08 && dip == nil
        if upright, let ratio = kneeRatio(frame) {
            // Standing only: a quarter squat leaves the counter at rest, but its frames must not
            // drag down what the knees look like standing.
            standingKneeRatio = standingKneeRatio.map { 0.9 * $0 + 0.1 * ratio } ?? ratio
        }
        // Knees caving shows anywhere in the movement, often on the way up, not only at the
        // bottom: count the frames.
        if (progress ?? 0) >= 0.15, let ratio = kneeRatio(frame), let standing = standingKneeRatio,
           let facing = Positioning.facingRatio(frame), facing >= 0.45, ratio < 0.8 * standing {
            caveFrames += 1
        }
        if inRep {
            if let bottom = bottomness(frame, progress: progress, depth: depth), bottom >= (deepest?.depth ?? -.infinity) {
                deepest = (bottom, frame)
            }
            if let depth { maxDepth = max(maxDepth ?? depth, depth) }
            if let progress { maxProgress = max(maxProgress ?? progress, progress) }
        } else if let elbow = elbowAngle(frame) {
            restElbow = max(restElbow ?? 0, elbow)
        }
    }

    /// A counted rep finished: its faults, and those to say now (each fault the first time it
    /// shows in the workout; after that it is only shown).
    public mutating func repCounted() -> (faults: Set<FormFault>, say: [FormFault]) {
        var faults: Set<FormFault> = []
        if let (_, frame) = deepest {
            if let d = maxProgress { depths.append(d) }
            faults = posture(at: frame)
        }
        maxDepth = nil
        maxProgress = nil
        if exercise == .pullUp, let elbow = restElbow, elbow < 150 { faults.insert(.armsBent) }
        reps.append(faults)
        attempts.append(faults)
        deepest = nil
        restElbow = nil
        dip?.handled = true
        caveFrames = 0
        return (faults, firstTime(faults))
    }

    /// A rep that started but turned back before full depth: its posture still counts.
    public mutating func repPartial() -> (faults: Set<FormFault>, say: [FormFault]) {
        // Before the first counted rep, a dip is getting set or walking in, not a short rep.
        if !reps.isEmpty { partials += 1 }
        let faults = deepest.map { posture(at: $0.frame) } ?? []
        attempts.append(faults)
        deepest = nil
        maxDepth = nil
        maxProgress = nil
        restElbow = nil
        dip?.handled = true
        caveFrames = 0
        return (faults, firstTime(faults))
    }

    /// The shallow dip that just ended, if one did (see `ShallowRep`).
    public mutating func takeShallowRep() -> ShallowRep? {
        defer { shallow = nil }
        return shallow
    }

    private mutating func firstTime(_ faults: Set<FormFault>) -> [FormFault] {
        let say = faults.filter { $0.live != nil && !spoken.contains($0) }.sorted { $0.rawValue < $1.rawValue }
        spoken.formUnion(say)
        return say
    }

    /// Follows dips the counter ignores because they stay above its start (0.4), for the
    /// exercises done with the feet planted, so walking or shifting weight is not taken for one.
    private mutating func watchDips(_ frame: PoseFrame, progress: Double?, depth: Double?) {
        guard [.squat, .romanianDeadlift].contains(exercise), let progress else { return }
        if progress >= 0.2 {
            var d = dip ?? Dip(start: frame.time, peak: progress, ankles: ankles(frame))
            d.peak = max(d.peak, progress)
            if let b = bottomness(frame, progress: progress, depth: depth), b >= (d.bottom?.depth ?? -.infinity) {
                d.bottom = (b, frame)
            }
            if let start = d.ankles, let now = ankles(frame), let torso = torsoLength(frame) {
                d.drift = max(d.drift, zip(start, now).map { ($0 - $1).length / torso }.max() ?? 0)
            }
            dip = d
        } else if progress <= 0.08, let d = dip {
            dip = nil
            defer { if !d.handled { caveFrames = 0 } }
            let duration = frame.time - d.start
            guard !d.handled, d.peak < 0.4, (0.3...5).contains(duration), d.ankles != nil, d.drift < 0.25,
                  let bottom = d.bottom
            else { return }
            let faults = posture(at: bottom.frame)
            caveFrames = 0
            attempts.append(faults)
            if !reps.isEmpty { partials += 1 }
            shallow = ShallowRep(depth: d.peak, faults: faults, say: firstTime(faults))
        }
    }

    private func ankles(_ f: PoseFrame) -> [Vec2]? {
        guard let l = f.point(.leftAnkle), let r = f.point(.rightAnkle) else { return nil }
        return [l, r]
    }

    private func torsoLength(_ f: PoseFrame) -> Double? {
        guard let s = f.meanY([.leftShoulder, .rightShoulder]), let h = f.meanY([.leftHip, .rightHip]), s - h > 0.02 else { return nil }
        return s - h
    }

    /// Up to three faults worth mentioning about the set just finished, most important first,
    /// and starts over for the next set. Empty means nothing to fix.
    public mutating func setFinished() -> [FormFault] {
        defer {
            reps = []
            attempts = []
            depths = []
            partials = 0
            deepest = nil
        }
        var faults: [FormFault] = []
        // Posture first, by how often it happened over every attempt in the set, counted or not;
        // a fault on a third of them or more.
        let posture = FormFault.allCases.filter { f in
            let n = attempts.filter { $0.contains(f) }.count
            return n > 0 && Double(n) >= Double(attempts.count) / 3
        }
        faults += posture.sorted { a, b in
            attempts.filter { $0.contains(a) }.count > attempts.filter { $0.contains(b) }.count
        }
        if partials >= 2 { faults.append(.shallow) }
        if depths.count >= 6, [.squat, .lunge, .pushUp].contains(exercise) {
            // Only when the last reps barely made the depth that counts, not when they are merely
            // less extreme than the first. (The counting depth, corrected for facing the phone.)
            let first = depths.prefix(3).reduce(0, +) / 3, last = depths.suffix(3).reduce(0, +) / 3
            if first - last > 0.12, last < exercise.thresholds.peak + 0.07 { faults.append(.fadingDepth) }
        }
        return Array(faults.prefix(3))
    }

    /// Said after a clean set, about what was actually measured.
    public static func praise(_ exercise: Exercise) -> String {
        switch exercise {
        case .squat, .lunge: "Good depth on every rep."
        case .pushUp: "Straight body and full depth on every rep."
        case .pullUp: "Full range on every rep."
        case .romanianDeadlift: "Good hinge on every rep."
        case .latPulldown, .crunch, .armRaise: "Full range on every rep."
        }
    }

    // MARK: - Measurements

    private func posture(at f: PoseFrame) -> Set<FormFault> {
        var faults: Set<FormFault> = []
        let ratio = Positioning.facingRatio(f)
        switch exercise {
        case .squat:
            // Facing the phone: knee spread against ankle spread, compared with standing, so a
            // wide or narrow stance does not matter. Knees pushed out over the toes widen it;
            // caving in narrows it below 0.8 of standing, on at least two frames of the
            // movement (counted in `observe`). (Perspective makes knees coming towards the lens
            // look wider, so this errs towards not flagging.)
            if caveFrames >= 2 { faults.insert(.kneesCaveIn) }
            // Side-on: the torso should lean about as far as the shins, no more (NASM).
            if let ratio, ratio < 0.3, let torso = tiltFromVertical(f, \.shoulder, \.hip),
               let shin = tiltFromVertical(f, \.knee, \.ankle), torso - shin > 25 {
                faults.insert(.forwardLean)
            }
        case .romanianDeadlift:
            // Side-on: the knee angle at the bottom. Coaches' RDLs on video measure 135–155°,
            // dipping to about 120° on some frames; a squat pattern is near 90°. Under 115° the
            // knees did most of the work.
            if let ratio, ratio < 0.3, let side = f.bestSide({ [$0.hip, $0.knee, $0.ankle] }),
               let knee = f.angle(side.hip, side.knee, side.ankle), knee < 115 {
                faults.insert(.kneesTooBent)
            }
        case .pushUp:
            // Side-on: how far the hips bend the shoulder–hip–ankle line, and which way.
            if let side = f.bestSide({ [$0.shoulder, $0.hip, $0.ankle] }),
               let s = f.point(side.shoulder), let h = f.point(side.hip), let a = f.point(side.ankle),
               let angle = f.angle(side.shoulder, side.hip, side.ankle), angle < 160 {
                // Where the hip sits against the straight shoulder–ankle line.
                let t = (h.x - s.x) / (a.x - s.x)
                let lineY = s.y + t * (a.y - s.y)
                faults.insert(h.y < lineY ? .hipsSag : .hipsPike)
            }
        case .lunge, .pullUp, .latPulldown, .crunch, .armRaise:
            break
        }
        return faults
    }

    /// How near the bottom of the rep a frame is, without the cap at 1 the counting signal has
    /// (it reaches 1 before the true bottom, and the posture must be read at the true bottom).
    private func bottomness(_ f: PoseFrame, progress: Double?, depth: Double?) -> Double? {
        switch exercise {
        case .romanianDeadlift: tiltFromVertical(f, \.shoulder, \.hip)
        case .pushUp: Side.allCases.compactMap { f.angle($0.shoulder, $0.elbow, $0.wrist) }.min().map { 180 - $0 }
        default: depth ?? progress
        }
    }

    private func kneeRatio(_ f: PoseFrame) -> Double? {
        guard exercise == .squat,
              let lk = f.point(.leftKnee), let rk = f.point(.rightKnee),
              let la = f.point(.leftAnkle), let ra = f.point(.rightAnkle)
        else { return nil }
        let ankles = abs(la.x - ra.x)
        guard ankles > 0.02 else { return nil }
        return abs(lk.x - rk.x) / ankles
    }

    private func elbowAngle(_ f: PoseFrame) -> Double? {
        guard exercise == .pullUp else { return nil }
        let angles = Side.allCases.compactMap { f.angle($0.shoulder, $0.elbow, $0.wrist) }
        return angles.min()
    }

    /// Degrees a segment leans from vertical, on the side seen best.
    private func tiltFromVertical(_ f: PoseFrame, _ top: KeyPath<Side, Joint>, _ bottom: KeyPath<Side, Joint>) -> Double? {
        guard let side = f.bestSide({ [$0[keyPath: top], $0[keyPath: bottom]] }),
              let a = f.point(side[keyPath: top]), let b = f.point(side[keyPath: bottom])
        else { return nil }
        let d = a - b
        return atan2(abs(d.x), d.y) * 180 / .pi
    }
}
