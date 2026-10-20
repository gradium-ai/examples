import Foundation
import RepCoachCore

// Checks for the counting logic on synthetic movement. `swift run repcoach-check`; exits 1 on
// any failure.

var failures = 0
var checks = 0

@MainActor func check(_ name: String, _ condition: Bool, _ detail: @autoclosure () -> String = "") {
    checks += 1
    if condition {
        print("  ok    \(name)")
    } else {
        failures += 1
        print("  FAIL  \(name) \(detail())")
    }
}

struct Result {
    var sets: [Int]
    var reps: [(set: Int, number: Int, time: TimeInterval)]
    var partials: Int
    var discarded: [Int]
    /// Form faults seen, per rep that had any, and the advice after each set.
    var faults: [Set<FormFault>] = []
    var spoken: [FormFault] = []
    var setForm: [[FormFault]] = []
}

func run(_ exercise: Exercise, _ performer: Performer, restTimeout: TimeInterval = 10) -> Result {
    var pipeline = RepPipeline(exercise: exercise, restTimeout: restTimeout)
    var result = Result(sets: [], reps: [], partials: 0, discarded: [])
    var t = 0.0
    func handle(_ end: SetEnd) {
        if end.discarded { result.discarded.append(end.reps) } else { result.setForm.append(end.form) }
    }
    for frame in performer.frames {
        t += 1 / Performer.fps
        guard let frame else {
            for case let .setEnd(end) in pipeline.missing(at: t) { handle(end) }
            continue
        }
        for output in pipeline.process(frame) {
            switch output {
            case let .rep(set, number, _): result.reps.append((set, number, frame.time))
            case .partial: result.partials += 1
            case let .setEnd(end): handle(end)
            case let .form(faults, say):
                result.faults.append(faults)
                result.spoken += say
            }
        }
    }
    result.sets = pipeline.finish(at: t + 60).sets
    if !pipeline.lastSetForm.isEmpty { result.setForm.append(pipeline.lastSetForm) }
    return result
}

print("squat")
do {
    var p = Performer()
    p.hold(2, Performer.squat)
    p.reps(10, Performer.squat); p.hold(15, Performer.squat)
    p.reps(8, Performer.squat); p.hold(15, Performer.squat)
    p.reps(6, Performer.squat)
    let r = run(.squat, p)
    check("three sets split by rest", r.sets == [10, 8, 6], "got \(r.sets)")
    check("rep numbers restart each set", r.reps.map(\.number).prefix(12) == [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 1, 2], "got \(r.reps.map(\.number))")
}
do {
    var p = Performer()
    p.hold(2, Performer.squat)
    p.reps(5, Performer.squat)
    p.reps(3, Performer.squat, depth: 0.55)
    p.reps(2, Performer.squat)
    let r = run(.squat, p)
    check("half squats do not count", r.sets == [7], "got \(r.sets)")
    check("half squats are reported as partial", r.partials == 3, "got \(r.partials)")
}
do {
    var p = Performer()
    p.noise = 0.009
    p.dropRate = 0.1
    p.rng = SeededRandom(seed: 7)
    p.hold(2, Performer.squat)
    p.reps(12, Performer.squat)
    let r = run(.squat, p)
    check("noisy landmarks and dropped frames", r.sets == [12], "got \(r.sets)")
}
do {
    var p = Performer()
    p.hold(2, Performer.squat, at: 1)   // session starts at the bottom
    p.rep(Performer.squat, depth: 0)    // stands up
    p.reps(4, Performer.squat)
    let r = run(.squat, p)
    check("starting at the bottom is not a rep", r.sets == [4], "got \(r.sets)")
}
do {
    var p = Performer()
    p.hold(2, Performer.squat)
    p.reps(8, Performer.squat); p.hold(12, Performer.squat)
    p.reps(1, Performer.squat); p.hold(12, Performer.squat)  // picking up a plate
    p.reps(8, Performer.squat)
    let r = run(.squat, p)
    check("a single stray rep between sets is dropped", r.sets == [8, 8] && r.discarded == [1], "got \(r.sets), discarded \(r.discarded)")
}
do {
    var p = Performer()
    p.hold(2, Performer.squat)
    p.reps(6, Performer.squat); p.hold(12, Performer.squat)
    p.absent(4)                       // walks off and comes back further away
    p.scale = 0.7
    p.hold(5, Performer.squat)
    p.reps(6, Performer.squat)
    let r = run(.squat, p)
    check("recalibrates after stepping back", r.sets == [6, 6], "got \(r.sets)")
}
do {
    var p = Performer()
    p.hold(2, Performer.squat)
    p.reps(3, Performer.squat)
    p.absent(1.5)                     // occluded mid-workout (someone walks past)
    p.reps(3, Performer.squat)
    let r = run(.squat, p)
    check("brief occlusion between reps", r.sets == [6], "got \(r.sets)")
}
do {
    var p = Performer()
    p.hold(2, Performer.squat)
    p.reps(3, Performer.squat)
    p.hold(1, Performer.squat, at: 1)  // at the bottom of a squat...
    p.absent(3)                        // ...walks out of view...
    p.hold(2, Performer.squat)         // ...and comes back standing
    p.reps(3, Performer.squat)
    let r = run(.squat, p)
    check("leaving view mid-rep does not count", r.sets == [6], "got \(r.sets)")
}

do {
    // Facing the phone, a squat to just above parallel: the case that failed in the gym.
    var p = Performer()
    p.hold(2, Performer.squatFacingPhone)
    p.reps(8, Performer.squatFacingPhone, depth: 0.85)
    let r = run(.squat, p)
    check("squats facing the phone, just above parallel", r.sets == [8], "got \(r.sets), partials \(r.partials)")
}
do {
    var p = Performer()
    p.hold(2, Performer.squatFacingPhone)
    p.reps(5, Performer.squatFacingPhone)
    p.reps(3, Performer.squatFacingPhone, depth: 0.4)
    let r = run(.squat, p)
    check("half squats facing the phone do not count", r.sets == [5], "got \(r.sets), partials \(r.partials)")
}

print("pull-up")
do {
    var p = Performer()
    p.hold(2, Performer.pullUp, at: -1)  // standing under the bar
    p.hold(1.5, Performer.pullUp, at: 0) // hangs
    p.reps(6, Performer.pullUp)
    p.hold(2, Performer.pullUp, at: -1)  // drops off
    let r = run(.pullUp, p)
    check("six pull-ups", r.sets == [6], "got \(r.sets)")
    // Counted at the top: the first rep's count lands mid-rep, well before it is back at rest.
    let firstRepEnds = 3.5 + 1 + 0.2 + 1
    check("counted with chin over the bar", (r.reps.first?.time ?? 99) < firstRepEnds - 0.8, "first count at \(r.reps.first?.time ?? -1)")
}
do {
    var p = Performer()
    p.hold(1.5, Performer.pullUp, at: 0)
    p.reps(3, Performer.pullUp)
    p.reps(2, Performer.pullUp, depth: 0.6)  // chin never reaches the bar
    p.reps(1, Performer.pullUp)
    let r = run(.pullUp, p)
    check("pull-ups short of the bar do not count", r.sets == [4] && r.partials == 2, "got \(r.sets), partials \(r.partials)")
}
do {
    var p = Performer()
    p.hold(1.5, Performer.pullUp, at: -1)
    p.hold(1, Performer.pullUp, at: 1)       // jumps straight to the top
    p.hold(1, Performer.pullUp, at: 0)       // lowers
    p.reps(3, Performer.pullUp)
    let r = run(.pullUp, p)
    check("jumping to the top is not a rep", r.sets == [3], "got \(r.sets)")
}

print("lat pulldown")
do {
    var p = Performer()
    p.hold(2, Performer.latPulldown)
    p.reps(12, Performer.latPulldown); p.hold(15, Performer.latPulldown)
    p.reps(10, Performer.latPulldown)
    let r = run(.latPulldown, p)
    check("two sets of pulldowns", r.sets == [12, 10], "got \(r.sets)")
    // Counted with the bar at the chest: the first count lands before the arms go back up.
    let firstRepEnds = 2 + 1 + 0.2 + 1
    check("pulldowns counted at the bottom of the pull", (r.reps.first?.time ?? 99) < firstRepEnds - 0.8, "first count at \(r.reps.first?.time ?? -1)")
}
do {
    var p = Performer()
    p.hold(2, Performer.latPulldown)
    p.reps(4, Performer.latPulldown)
    p.reps(2, Performer.latPulldown, depth: 0.5)
    let r = run(.latPulldown, p)
    check("half pulldowns do not count", r.sets == [4] && r.partials == 2, "got \(r.sets), partials \(r.partials)")
}

print("push-up")
do {
    var p = Performer()
    p.hold(2, Performer.pushUp, at: -1)  // standing next to the phone
    p.hold(1.5, Performer.pushUp, at: 0)
    p.reps(15, Performer.pushUp)
    p.hold(3, Performer.pushUp, at: -1)  // stands back up
    let r = run(.pushUp, p)
    check("fifteen push-ups", r.sets == [15], "got \(r.sets)")
}
do {
    var p = Performer()
    p.hold(1.5, Performer.pushUp, at: 0)
    p.reps(5, Performer.pushUp)
    p.reps(3, Performer.pushUp, depth: 0.4)
    let r = run(.pushUp, p)
    check("shallow push-ups do not count", r.sets == [5], "got \(r.sets)")
}

print("arm raise")
do {
    var p = Performer()
    p.hold(2, Performer.armRaise)
    p.reps(10, Performer.armRaise); p.hold(15, Performer.armRaise)
    p.reps(8, Performer.armRaise)
    let r = run(.armRaise, p)
    check("two sets of arm raises", r.sets == [10, 8], "got \(r.sets)")
}
do {
    var p = Performer()
    p.hold(2, Performer.armRaise)
    p.reps(4, Performer.armRaise)
    p.reps(3, Performer.armRaise, depth: 0.5)          // only out to a T
    p.reps(2, { Performer.armRaise($0, leftOnly: true) })
    p.reps(2, Performer.armRaise)
    let r = run(.armRaise, p)
    check("T-raises and one-arm raises do not count", r.sets == [6] && r.partials == 3, "got \(r.sets), partials \(r.partials)")
}
do {
    var p = Performer()
    p.scale = 0.6                                     // standing further back
    p.hold(2, Performer.armRaise)
    p.reps(5, Performer.armRaise)
    let r = run(.armRaise, p)
    check("arm raises from further away", r.sets == [5], "got \(r.sets)")
}

print("lunge")
do {
    var p = Performer()
    p.hold(2, { Performer.lunge($0, front: .left) })
    for i in 0..<12 { p.rep({ Performer.lunge($0, front: i % 2 == 0 ? .left : .right) }) }
    let r = run(.lunge, p)
    check("twelve alternating lunges", r.sets == [12], "got \(r.sets)")
}
do {
    var p = Performer()
    p.hold(2, { Performer.lunge($0, front: .left) })
    p.reps(4, { Performer.lunge($0, front: .left) })
    p.reps(3, { Performer.lunge($0, front: .right) }, depth: 0.35)
    let r = run(.lunge, p)
    check("shallow lunges do not count", r.sets == [4] && r.partials == 0, "got \(r.sets), partials \(r.partials)")
}

print("Romanian deadlift")
do {
    var p = Performer()
    p.hold(2, Performer.romanianDeadlift)
    p.reps(10, Performer.romanianDeadlift); p.hold(15, Performer.romanianDeadlift)
    p.reps(8, Performer.romanianDeadlift)
    let r = run(.romanianDeadlift, p)
    check("two sets of Romanian deadlifts", r.sets == [10, 8], "got \(r.sets)")
}
do {
    var p = Performer()
    p.hold(2, Performer.romanianDeadlift)
    p.reps(5, Performer.romanianDeadlift)
    p.reps(3, Performer.romanianDeadlift, depth: 0.3)   // a nod, not a hinge
    let r = run(.romanianDeadlift, p)
    check("small hinges do not count", r.sets == [5], "got \(r.sets)")
}
do {
    var p = Performer()
    p.hold(2, Performer.romanianDeadliftFront)
    p.reps(6, Performer.romanianDeadliftFront)
    let r = run(.romanianDeadlift, p)
    check("Romanian deadlifts from the front", r.sets == [6], "got \(r.sets)")
}

print("crunch")
do {
    var p = Performer()
    p.hold(2, Performer.crunch, at: -1)    // standing by the phone
    p.hold(2, Performer.crunch, at: 0)     // lies down
    p.reps(15, Performer.crunch)
    p.hold(2, Performer.crunch, at: -1)
    let r = run(.crunch, p)
    check("fifteen crunches", r.sets == [15], "got \(r.sets)")
}
do {
    var p = Performer()
    p.hold(2, Performer.crunch, at: 0)
    p.reps(5, Performer.crunch)
    p.reps(3, Performer.crunch, depth: 0.25)     // head nods
    let r = run(.crunch, p)
    check("head nods do not count", r.sets == [5], "got \(r.sets)")
}
do {
    var p = Performer()
    p.hold(2, { Performer.crunch($0, floor: 6) }, at: 0)
    p.reps(8, { Performer.crunch($0, floor: 6) })
    let r = run(.crunch, p)
    check("crunches on a slope", r.sets == [8], "got \(r.sets)")
}

print("form")
do {
    var p = Performer()
    p.hold(2, Performer.squatFacingPhone)
    p.reps(6, Performer.squatFacingPhone)
    let r = run(.squat, p)
    check("good squats facing the phone: no faults", r.faults.isEmpty && r.setForm.allSatisfy(\.isEmpty), "got \(r.faults), \(r.setForm)")
}
do {
    var p = Performer()
    p.hold(2, { Performer.squatFacingPhone($0, kneesIn: false) })
    p.reps(6, { Performer.squatFacingPhone($0, kneesIn: true) })
    let r = run(.squat, p)
    check("knees caving in: flagged, said once, advised", r.sets == [6] && r.faults.count == 6
          && r.spoken == [.kneesCaveIn] && r.setForm == [[.kneesCaveIn]], "got \(r.faults.count) \(r.spoken) \(r.setForm)")
}
do {
    var good = Performer(), leaning = Performer()
    good.hold(2, { Performer.squatSideOn($0, lean: 35) }); good.reps(5, { Performer.squatSideOn($0, lean: 35) })
    leaning.hold(2, { Performer.squatSideOn($0, lean: 70) }); leaning.reps(5, { Performer.squatSideOn($0, lean: 70) })
    let g = run(.squat, good), l = run(.squat, leaning)
    check("side-on squat, torso with the shins: fine", g.sets == [5] && g.faults.isEmpty, "got \(g.sets) \(g.faults)")
    check("side-on squat, torso far past the shins: lean", l.sets == [5] && l.setForm == [[.forwardLean]], "got \(l.sets) \(l.setForm)")
}
do {
    var p = Performer()
    p.hold(2, Performer.romanianDeadlift)
    p.reps(5, { Performer.romanianDeadlift($0, squatty: true) })
    let r = run(.romanianDeadlift, p)
    check("RDL squatted down: knees too bent", r.sets == [5] && r.setForm == [[.kneesTooBent]], "got \(r.sets) \(r.setForm)")
    var q = Performer()
    q.hold(2, Performer.romanianDeadlift); q.reps(5, Performer.romanianDeadlift)
    let ok = run(.romanianDeadlift, q)
    check("RDL with soft knees: fine", ok.faults.isEmpty, "got \(ok.faults)")
}
do {
    var sag = Performer(), pike = Performer(), plank = Performer()
    for (perf, hips) in [(0, -0.06), (1, 0.08), (2, 0.0)] {
        var p = Performer()
        p.hold(1.5, { Performer.pushUp($0, hips: hips) }, at: 0)
        p.reps(5, { Performer.pushUp($0, hips: hips) })
        if perf == 0 { sag = p } else if perf == 1 { pike = p } else { plank = p }
    }
    check("push-ups with sagging hips", run(.pushUp, sag).setForm == [[.hipsSag]], "got \(run(.pushUp, sag).setForm)")
    check("push-ups with piked hips", run(.pushUp, pike).setForm == [[.hipsPike]], "got \(run(.pushUp, pike).setForm)")
    check("push-ups in a straight line: fine", run(.pushUp, plank).faults.isEmpty, "got \(run(.pushUp, plank).faults)")
}
do {
    var p = Performer()
    p.hold(1, Performer.pullUp, at: 0)
    p.reps(5, Performer.pullUp)
    let r = run(.pullUp, p)
    check("pull-ups from a dead hang: fine", r.sets == [5] && r.faults.isEmpty, "got \(r.sets) \(r.faults)")
}
do {
    var p = Performer()
    p.hold(2, { Performer.squatSideOn($0, lean: 35) })
    for depth in [1.0, 1.0, 1.0, 0.97, 0.93, 0.92, 0.92, 0.91] { p.rep({ Performer.squatSideOn($0, lean: 35) }, depth: depth) }
    let r = run(.squat, p)
    check("squats getting shallower: go deeper on the last reps", r.sets == [8] && r.setForm == [[.fadingDepth]], "got \(r.sets) \(r.setForm)")
    p = Performer()
    p.hold(2, Performer.squat)
    p.reps(4, Performer.squat); p.reps(2, Performer.squat, depth: 0.5); p.reps(2, Performer.squat)
    let short = run(.squat, p)
    check("half squats mid-set: squat deeper", short.setForm == [[.shallow]], "got \(short.setForm)")
}
check("advice is at most three sentences", Coach.formFeedback(FormFault.allCases, reps: 10, exercise: .squat).count == 3)
check("a clean set gets one line of praise", Coach.formFeedback([], reps: 8, exercise: .squat).map(\.text) == ["Good depth on every rep."])
check("every form phrase is precomputed", FormFault.allPhrases.allSatisfy(PhraseBook.precomputed.contains))

print("positioning")
do {
    func frame(_ body: Performer.Body, scale: Double = 1, shiftX: Double = 0) -> PoseFrame {
        var p = Performer()
        p.noise = 0
        p.scale = scale
        p.hold(1 / Performer.fps, { _ in body.mapValues { Vec2($0.x + shiftX, $0.y) } })
        return p.frames[0]!
    }
    func cue(_ e: Exercise, _ f: PoseFrame?) -> Cue { Positioning.guidance(for: e, frame: f).cue }
    check("nobody: step into view", cue(.squat, nil) == .stepIntoView)
    check("standing in the middle: ready", cue(.squat, frame(Performer.squat(0))) == .ready, "got \(cue(.squat, frame(Performer.squat(0))))")
    let tooBig = frame(Performer.squat(0), scale: 1.5)
    check("too close: step back", cue(.squat, tooBig) == .stepBack, "got \(cue(.squat, tooBig))")
    let tooSmall = frame(Performer.squat(0), scale: 0.4)
    check("too far: come closer", cue(.squat, tooSmall) == .comeCloser, "got \(cue(.squat, tooSmall))")
    let offLeft = Positioning.guidance(for: .squat, frame: frame(Performer.squat(0), shiftX: -0.2))
    check("off the left edge, facing the phone: move to your right",
          offLeft.cue == .move(.yourRight) && offLeft.direction == .right && offLeft.edges == [.left], "got \(offLeft)")
    let sideOff = Positioning.guidance(for: .lunge, frame: frame(Performer.lunge(0, front: .left), shiftX: 0.27))
    check("side-on, off the right edge, facing right: step backwards", sideOff.cue == .move(.backwards), "got \(sideOff)")
    check("lunge facing the phone: turn sideways", cue(.lunge, frame(Performer.squat(0))) == .turnSideways,
          "got \(cue(.lunge, frame(Performer.squat(0))))")
    check("lunge side-on: ready", cue(.lunge, frame(Performer.lunge(0, front: .left))) == .ready,
          "got \(cue(.lunge, frame(Performer.lunge(0, front: .left))))")
    check("arm raise side-on: face the phone", cue(.armRaise, frame(Performer.lunge(0, front: .left))) == .faceThePhone)
    check("crunch standing: lie down", cue(.crunch, frame(Performer.crunch(-1))) == .lieDown, "got \(cue(.crunch, frame(Performer.crunch(-1))))")
    // Lying down, a body is wider than a portrait picture is: further away it fits.
    let lying = frame(Performer.crunch(0), scale: 0.65)
    check("crunch lying, far enough away: ready", cue(.crunch, lying) == .ready, "got \(cue(.crunch, lying))")
    check("crunch lying, too close: step back", cue(.crunch, frame(Performer.crunch(0))) == .stepBack)
    var noKnees = Performer.squat(0)
    noKnees[.leftKnee] = nil; noKnees[.rightKnee] = nil; noKnees[.leftAnkle] = nil; noKnees[.rightAnkle] = nil
    check("knees hidden: say so", cue(.squat, frame(noKnees)) == .cantSee(.knees), "got \(cue(.squat, frame(noKnees)))")
    var filter = GuidanceFilter(hold: 0.5)
    _ = filter.update(Guidance(cue: .stepBack), at: 0)
    _ = filter.update(Guidance(cue: .ready), at: 0.1)      // one frame of ready
    _ = filter.update(Guidance(cue: .stepBack), at: 0.2)
    check("a one-frame flicker does not change the direction", filter.shown?.cue == .stepBack)
    for t in stride(from: 0.3, through: 1.0, by: 0.1) { _ = filter.update(Guidance(cue: .ready), at: t) }
    check("a steady new direction takes over", filter.shown?.cue == .ready && abs(filter.held(at: 1.0) - 0.7) < 0.01,
          "got \(String(describing: filter.shown?.cue)), held \(filter.held(at: 1.0))")
    check("every cue is precomputed", Cue.all.allSatisfy { PhraseBook.precomputed.contains($0.text) })
}

print("geometry")
do {
    // A right angle in pixels: (0,0.5)-(0,0)-(0.5,0) in aspect-correct units. In normalized
    // portrait coordinates the horizontal leg is 0.5 / 0.5625 wide.
    let aspect = 0.5625
    let f = PoseFrame(time: 0, aspect: aspect, joints: [
        .leftShoulder: Vec2(0, 0.5), .leftElbow: Vec2(0, 0), .leftWrist: Vec2(0.5 / aspect, 0),
    ])
    let a = f.angle(.leftShoulder, .leftElbow, .leftWrist) ?? 0
    check("angles use aspect-correct coordinates", abs(a - 90) < 0.01, "got \(a)")
    let low = PoseFrame(time: 0, aspect: aspect, joints: [.nose: Vec2(0.5, 0.5)], confidence: [.nose: 0.1])
    check("low-confidence joints are not seen", !low.sees(.nose))
}

print("coach")
do {
    var coach = Coach(target: 10, motivation: true)
    let lines = (1...12).map { coach.rep($0).map(\.text) }
    check("counts every rep", lines.map { $0.first } == (1...12).map(PhraseBook.count))
    check("two more at 8", lines[7] == ["Eight!", PhraseBook.twoMore], "got \(lines[7])")
    check("last one at 9", lines[8] == ["Nine!", PhraseBook.lastOne], "got \(lines[8])")
    check("target at 10", lines[9] == ["Ten!", PhraseBook.targetHit], "got \(lines[9])")
    check("one more past the target", lines[10] == ["Eleven!", PhraseBook.pastTarget[0]], "got \(lines[10])")
    check("quiet below the target", lines[0...6].allSatisfy { $0.count == 1 })
    check("compound numbers", PhraseBook.count(21) == "Twenty-one!", "got \(PhraseBook.count(21))")

    var quiet = Coach(target: 10, motivation: false)
    check("motivation off says only counts", (1...12).allSatisfy { quiet.rep($0).count == 1 })

    let everyLine = (1...14).flatMap { coach.rep($0) }
    check("everything said mid-set is precomputed", everyLine.allSatisfy { $0.precomputed && PhraseBook.precomputed.contains($0.text) })

    let s = coach.summary(WorkoutSummary(exercise: .squat, sets: [10, 10, 8], duration: 600))
    check("summary", s.text == "Workout done. 3 sets of squats: 10, 10 and 8. 28 reps in total. Nice work!", "got \(s.text)")
    check("discarded sets are not announced", coach.setEnded(SetEnd(setNumber: 2, reps: 1, discarded: true)) == nil)
}

print("recording")
do {
    var p = Performer()
    p.hold(1, Performer.squat)
    p.reps(3, Performer.squat)
    let frames = p.frames.compactMap { $0 }
    var data = try! PoseRecording.encode(PoseRecording.Header(exercise: .squat, aspect: frames[0].aspect))
    for f in frames { data += try! PoseRecording.encode(f) }
    let (header, decoded) = try! PoseRecording.decode(data)
    check("round trip keeps every frame", header.exercise == .squat && decoded.count == frames.count)
    var pipeline = RepPipeline(exercise: .squat)
    let reps = decoded.flatMap { pipeline.process($0) }.filter { if case .rep = $0 { true } else { false } }
    check("replayed recording counts the same", reps.count == 3, "got \(reps.count)")

    // Version 2: gravity, rotated poses and AirPods samples interleaved with the frames.
    var v2 = try! PoseRecording.encode(PoseRecording.Header(exercise: .pushUp, aspect: frames[0].aspect))
    let rotated = PoseFrame(time: frames[0].time, aspect: 1 / frames[0].aspect, joints: [.leftElbow: Vec2(0.25, 0.5)], confidence: [.leftElbow: 0.7])
    let extras = PoseRecording.Extras(gravity: Vec3(-0.98, 0.02, -0.1), rotated: ["left": rotated])
    let head = HeadMotion(time: frames[0].time + 0.01, attitude: [0, 0, 0, 1], userAcceleration: Vec3(0, -0.2, 0),
                          rotationRate: Vec3(0.1, 0, 0), gravity: Vec3(0, -1, 0), sensor: "left")
    v2 += try! PoseRecording.encode(frames[0], extras: extras)
    v2 += try! PoseRecording.encode(head)
    v2 += try! PoseRecording.encode(PoseFrame(time: frames[1].time, aspect: frames[0].aspect, joints: [:]))
    let (_, entries) = try! PoseRecording.decodeEntries(v2)
    check("v2 keeps frames, extras and head motion in order", entries.count == 3)
    if case let .frame(f, e) = entries[0] {
        check("v2 gravity and rotated pose", e.gravity == extras.gravity && e.rotated["left"]?.joints[.leftElbow] == Vec2(0.25, 0.5) && f.joints.count == frames[0].joints.count)
    } else { check("v2 first entry is a frame", false) }
    check("v2 head sample", entries[1] == .head(head), "got \(entries[1])")
    check("v2 frames-only decode skips head samples", (try! PoseRecording.decode(v2)).1.count == 2)

    // A version 1 line (no extras, no version in the header) still reads.
    let v1 = Data("{\"exercise\":\"squat\",\"aspect\":0.5625,\"recordedAt\":\"2026-10-06T10:00:00Z\"}\n{\"t\":1,\"j\":{\"nose\":[0.5,0.8,0.9]}}\n".utf8)
    let (h1, f1) = try! PoseRecording.decode(v1)
    check("version 1 recordings still read", h1.version == nil && f1.count == 1 && f1[0].sees(.nose))
}

print("\(checks - failures)/\(checks) checks passed")
exit(failures == 0 ? 0 : 1)
