import Foundation
import RepCoachCore

/// Deterministic noise, so a failing check fails the same way every run.
struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z >> 11) / Double(1 << 53)
    }

    mutating func gaussian(_ sigma: Double) -> Double {
        let u1 = max(next(), 1e-12), u2 = next()
        return sigma * (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
    }
}

/// Generates pose frames for a person doing an exercise in a portrait 720×1280 frame.
///
/// Positions are written in aspect-correct units (x in 0…aspect, y in 0…1) and converted to
/// Vision's normalized coordinates on output, so the generator exercises the aspect handling.
struct Performer {
    static let fps = 15.0
    let aspect = 720.0 / 1280.0
    var noise = 0.004
    /// Fraction of frames where the pose is not found at all.
    var dropRate = 0.0
    /// Body size in the frame: 1 is a person filling most of its height.
    var scale = 1.0
    var rng = SeededRandom(seed: 42)
    private(set) var time = 0.0
    private(set) var frames: [PoseFrame?] = []

    typealias Body = [Joint: Vec2]

    // MARK: Motion

    /// Holds a pose (u = how deep into the rep) for `seconds`.
    mutating func hold(_ seconds: Double, _ pose: (Double) -> Body, at u: Double = 0) {
        for _ in 0..<Int(seconds * Self.fps) { emit(pose(u)) }
    }

    /// One rep: down to `depth` over `down` seconds, a short pause, then back up.
    mutating func rep(_ pose: (Double) -> Body, depth: Double = 1, down: Double = 1, up: Double = 1) {
        let n = Int(down * Self.fps)
        for i in 0..<n { emit(pose(depth * ease(Double(i + 1) / Double(n)))) }
        hold(0.2, pose, at: depth)
        let m = Int(up * Self.fps)
        for i in 0..<m { emit(pose(depth * (1 - ease(Double(i + 1) / Double(m))))) }
        hold(0.4, pose, at: 0)
    }

    mutating func reps(_ count: Int, _ pose: (Double) -> Body, depth: Double = 1) {
        for _ in 0..<count { rep(pose, depth: depth) }
    }

    /// Nobody in view.
    mutating func absent(_ seconds: Double) {
        for _ in 0..<Int(seconds * Self.fps) { frames.append(nil); time += 1 / Self.fps }
    }

    private func ease(_ t: Double) -> Double { 0.5 - 0.5 * cos(.pi * t) }

    private mutating func emit(_ body: Body) {
        defer { time += 1 / Self.fps }
        if dropRate > 0, rng.next() < dropRate {
            frames.append(nil)
            return
        }
        var joints: [Joint: Vec2] = [:]
        var confidence: [Joint: Double] = [:]
        // In a fixed order: dictionary order changes between runs, and so would the noise.
        for (joint, p) in body.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            // Scale about the frame's centre-bottom, as standing further from the phone does.
            let x = aspect / 2 + (p.x - aspect / 2) * scale + rng.gaussian(noise)
            let y = p.y * scale + rng.gaussian(noise)
            joints[joint] = Vec2(x / aspect, y)
            confidence[joint] = 0.8
        }
        frames.append(PoseFrame(time: time, aspect: aspect, joints: joints, confidence: confidence))
    }

    // MARK: Bodies (aspect-correct units)

    /// Front-on squat. u = 1 puts the hip slightly below the knee.
    static func squat(_ u: Double) -> Body {
        let c = 720.0 / 1280.0 / 2
        let drop = u * 0.21
        let hipY = 0.5 - drop, shoulderY = 0.74 - drop * 1.05
        return [
            .nose: Vec2(c, shoulderY + 0.1),
            .leftShoulder: Vec2(c - 0.09, shoulderY), .rightShoulder: Vec2(c + 0.09, shoulderY),
            .leftElbow: Vec2(c - 0.1, shoulderY - 0.1), .rightElbow: Vec2(c + 0.1, shoulderY - 0.1),
            .leftWrist: Vec2(c - 0.1, shoulderY - 0.18), .rightWrist: Vec2(c + 0.1, shoulderY - 0.18),
            .leftHip: Vec2(c - 0.06, hipY), .rightHip: Vec2(c + 0.06, hipY),
            .leftKnee: Vec2(c - 0.07 - 0.03 * u, 0.29), .rightKnee: Vec2(c + 0.07 + 0.03 * u, 0.29),
            .leftAnkle: Vec2(c - 0.07, 0.08), .rightAnkle: Vec2(c + 0.07, 0.08),
        ]
    }

    /// Squat facing a phone at hip height 2.5 m away, through a pinhole camera: the knees come
    /// towards the lens and the hips go back, so on screen the knees look lower than they are.
    /// u = 1 puts the hip a little below the knee.
    static func squatFacingPhone(_ u: Double) -> Body { squatFacingPhone(u, kneesIn: false) }

    /// With `kneesIn`, the knees drift together on the way down instead of tracking the toes.
    static func squatFacingPhone(_ u: Double, kneesIn: Bool) -> Body {
        let c = 720.0 / 1280.0 / 2, cameraHeight = 0.9, focal = 1.11
        func project(_ x: Double, _ y: Double, _ z: Double) -> Vec2 {
            Vec2(c + focal * x / z, 0.5 + focal * (y - cameraHeight) / z)
        }
        let hipY = 0.92 - 0.47 * u, hipZ = 2.5 + 0.25 * u
        let kneeY = 0.5 - 0.02 * u, kneeZ = 2.5 - 0.3 * u, kneeX = kneesIn ? 0.1 - 0.07 * u : 0.1 + 0.05 * u
        let lean = 40 * u * .pi / 180
        let shoulderY = hipY + 0.5 * cos(lean), shoulderZ = hipZ - 0.5 * sin(lean)
        return [
            .nose: project(0, shoulderY + 0.2, shoulderZ - 0.05),
            .leftShoulder: project(-0.18, shoulderY, shoulderZ), .rightShoulder: project(0.18, shoulderY, shoulderZ),
            .leftElbow: project(-0.3, shoulderY, shoulderZ + 0.05), .rightElbow: project(0.3, shoulderY, shoulderZ + 0.05),
            .leftWrist: project(-0.4, shoulderY + 0.05, shoulderZ), .rightWrist: project(0.4, shoulderY + 0.05, shoulderZ),
            .leftHip: project(-0.08, hipY, hipZ), .rightHip: project(0.08, hipY, hipZ),
            .leftKnee: project(-kneeX, kneeY, kneeZ), .rightKnee: project(kneeX, kneeY, kneeZ),
            .leftAnkle: project(-0.1, 0.08, 2.5), .rightAnkle: project(0.1, 0.08, 2.5),
        ]
    }

    /// Squat side-on, facing right: the shins tip forward 30° at the bottom and the torso
    /// `lean` degrees from upright.
    static func squatSideOn(_ u: Double, lean: Double) -> Body {
        let c = 720.0 / 1280.0 / 2
        let ankle = Vec2(c + 0.05, 0.08), shin = 0.21, thigh = 0.21, torso = 0.24
        let shinAngle = 30 * u * .pi / 180
        let knee = Vec2(ankle.x + shin * sin(shinAngle), ankle.y + shin * cos(shinAngle))
        // The thigh goes from upright to level with the floor.
        let thighAngle = 90 * u * .pi / 180
        let hip = Vec2(knee.x - thigh * sin(thighAngle), knee.y + thigh * cos(thighAngle) * 0.95 + 0.01)
        let t = lean * u * .pi / 180
        let shoulder = Vec2(hip.x + torso * sin(t), hip.y + torso * cos(t))
        return [
            .nose: Vec2(shoulder.x + 0.05, shoulder.y + 0.08),
            .leftShoulder: shoulder, .rightShoulder: Vec2(shoulder.x + 0.005, shoulder.y),
            .leftElbow: Vec2(shoulder.x + 0.05, shoulder.y - 0.1), .rightElbow: Vec2(shoulder.x + 0.055, shoulder.y - 0.1),
            .leftWrist: Vec2(shoulder.x + 0.1, shoulder.y - 0.12), .rightWrist: Vec2(shoulder.x + 0.105, shoulder.y - 0.12),
            .leftHip: hip, .rightHip: Vec2(hip.x + 0.005, hip.y),
            .leftKnee: knee, .rightKnee: Vec2(knee.x + 0.005, knee.y),
            .leftAnkle: ankle, .rightAnkle: Vec2(ankle.x + 0.005, ankle.y),
        ]
    }

    /// Pull-up from the front, hands fixed on the bar at y = 0.85. u = 1 is the nose just over
    /// the bar; u < 0 means standing under the bar with arms down.
    static func pullUp(_ u: Double) -> Body {
        let c = 720.0 / 1280.0 / 2
        if u < 0 {  // standing, arms by the sides
            return squat(0)
        }
        let lift = u * 0.27
        let shoulderY = 0.6 + lift
        return [
            .nose: Vec2(c, shoulderY + 0.06),
            .leftShoulder: Vec2(c - 0.09, shoulderY), .rightShoulder: Vec2(c + 0.09, shoulderY),
            // On the shoulder–hand line at a dead hang (straight arms), flaring out as they bend.
            .leftElbow: Vec2(c - 0.12 - 0.06 * u, (shoulderY + 0.85) / 2), .rightElbow: Vec2(c + 0.12 + 0.06 * u, (shoulderY + 0.85) / 2),
            .leftWrist: Vec2(c - 0.15, 0.85), .rightWrist: Vec2(c + 0.15, 0.85),
            .leftHip: Vec2(c - 0.06, shoulderY - 0.24), .rightHip: Vec2(c + 0.06, shoulderY - 0.24),
            .leftKnee: Vec2(c - 0.06, shoulderY - 0.45), .rightKnee: Vec2(c + 0.06, shoulderY - 0.45),
        ]
    }

    /// Seated lat pulldown from the front; shoulders fixed, hands from overhead down to the chest.
    static func latPulldown(_ u: Double) -> Body {
        let c = 720.0 / 1280.0 / 2
        let wristY = 0.82 - u * 0.33
        return [
            .nose: Vec2(c, 0.58),
            .leftShoulder: Vec2(c - 0.09, 0.5), .rightShoulder: Vec2(c + 0.09, 0.5),
            .leftElbow: Vec2(c - 0.16 - 0.04 * u, (0.5 + wristY) / 2 - 0.05 * u), .rightElbow: Vec2(c + 0.16 + 0.04 * u, (0.5 + wristY) / 2 - 0.05 * u),
            .leftWrist: Vec2(c - 0.16, wristY), .rightWrist: Vec2(c + 0.16, wristY),
            .leftHip: Vec2(c - 0.06, 0.28), .rightHip: Vec2(c + 0.06, 0.28),
            .leftKnee: Vec2(c - 0.07, 0.2), .rightKnee: Vec2(c + 0.07, 0.2),
        ]
    }

    /// Standing arm raise from the front: both arms swing out to the sides and up, u = 0.5 is
    /// a T, u = 1 straight overhead. `leftOnly` raises just the left arm.
    static func armRaise(_ u: Double, leftOnly: Bool) -> Body {
        var body = squat(0)
        let arm = 0.2
        func hand(_ side: Double, _ shoulder: Vec2, _ v: Double) -> (Vec2, Vec2) {
            let theta = v * .pi   // 0: hanging down, pi: straight up
            let wrist = Vec2(shoulder.x + side * arm * sin(theta), shoulder.y - arm * cos(theta))
            let elbow = Vec2((shoulder.x + wrist.x) / 2, (shoulder.y + wrist.y) / 2)
            return (elbow, wrist)
        }
        let ls = body[.leftShoulder]!, rs = body[.rightShoulder]!
        (body[.leftElbow], body[.leftWrist]) = hand(-1, ls, u)
        (body[.rightElbow], body[.rightWrist]) = hand(1, rs, leftOnly ? 0 : u)
        return body
    }

    static func armRaise(_ u: Double) -> Body { armRaise(u, leftOnly: false) }

    /// Lunge side-on, facing right, stepping forward with `front`. u = 1 is the bottom: front
    /// thigh about level, back knee near the floor.
    static func lunge(_ u: Double, front: Side) -> Body {
        let c = 720.0 / 1280.0 / 2
        let hipY = 0.5 - 0.18 * u, shoulderY = 0.74 - 0.18 * u
        let frontKnee = Vec2(c + 0.12 * u, 0.29 - 0.02 * u), frontAnkle = Vec2(c + 0.16 * u, 0.08)
        let backKnee = Vec2(c - 0.05 * u, 0.29 - 0.17 * u), backAnkle = Vec2(c - 0.14 * u, 0.08)
        var body: Body = [
            .nose: Vec2(c + 0.02, shoulderY + 0.1),
            .leftShoulder: Vec2(c, shoulderY), .rightShoulder: Vec2(c + 0.01, shoulderY),
            .leftElbow: Vec2(c, shoulderY - 0.12), .rightElbow: Vec2(c + 0.01, shoulderY - 0.12),
            .leftWrist: Vec2(c, shoulderY - 0.22), .rightWrist: Vec2(c + 0.01, shoulderY - 0.22),
            .leftHip: Vec2(c, hipY), .rightHip: Vec2(c + 0.01, hipY),
        ]
        let back: Side = front == .left ? .right : .left
        body[front.knee] = frontKnee; body[front.ankle] = frontAnkle
        body[back.knee] = backKnee; body[back.ankle] = backAnkle
        return body
    }

    /// Romanian deadlift side-on, facing right: the torso tips forward about the hip, u = 1 is
    /// 75° from upright, the hips push back and the knees soften. With `squatty`, the knees
    /// bend deep and the hips drop instead.
    static func romanianDeadlift(_ u: Double) -> Body { romanianDeadlift(u, squatty: false) }

    static func romanianDeadlift(_ u: Double, squatty: Bool) -> Body {
        let c = 720.0 / 1280.0 / 2
        let theta = 75 * u * .pi / 180, torso = 0.24
        let hip = squatty ? Vec2(c - 0.1 * u, 0.5 - 0.15 * u) : Vec2(c - 0.05 * u, 0.5 - 0.02 * u)
        let knee = squatty ? Vec2(c + 0.1 * u, 0.29 - 0.02 * u) : Vec2(c + 0.02 * u, 0.29)
        let shoulder = Vec2(hip.x + torso * sin(theta), hip.y + torso * cos(theta))
        return [
            .nose: Vec2(shoulder.x + 0.06 * cos(theta) + 0.03, shoulder.y + 0.08 * cos(theta)),
            .leftShoulder: shoulder, .rightShoulder: Vec2(shoulder.x + 0.01, shoulder.y),
            .leftElbow: Vec2(shoulder.x, shoulder.y - 0.12), .rightElbow: Vec2(shoulder.x + 0.01, shoulder.y - 0.12),
            .leftWrist: Vec2(shoulder.x, shoulder.y - 0.22), .rightWrist: Vec2(shoulder.x + 0.01, shoulder.y - 0.22),
            .leftHip: hip, .rightHip: Vec2(hip.x + 0.01, hip.y),
            .leftKnee: knee, .rightKnee: Vec2(knee.x + 0.01, knee.y),
            .leftAnkle: Vec2(c, 0.08), .rightAnkle: Vec2(c + 0.01, 0.08),
        ]
    }

    /// The same, filmed from the front: the torso tips towards the lens, so on screen it only
    /// gets shorter.
    static func romanianDeadliftFront(_ u: Double) -> Body {
        var body = squat(0)
        let theta = 75 * u * .pi / 180, torso = 0.24
        let hipY = body[.leftHip]!.y, shoulderY = hipY + torso * cos(theta)
        for joint in [Joint.leftShoulder, .rightShoulder] { body[joint] = Vec2(body[joint]!.x, shoulderY) }
        for joint in [Joint.leftElbow, .rightElbow] { body[joint] = Vec2(body[joint]!.x, shoulderY - 0.1) }
        for joint in [Joint.leftWrist, .rightWrist] { body[joint] = Vec2(body[joint]!.x, shoulderY - 0.18) }
        body[.nose] = Vec2(body[.nose]!.x, shoulderY + 0.1 * cos(theta))
        return body
    }

    /// Crunch side-on, lying with the head to the left and knees bent: u = 1 curls the
    /// shoulders 25° off the floor. `floor` tilts the whole body, as a sloping mat or a tilted
    /// phone would. u < 0 means standing.
    static func crunch(_ u: Double, floor: Double) -> Body {
        if u < 0 { return squat(0) }
        let c = 720.0 / 1280.0 / 2
        let tilt = floor * .pi / 180, phi = 25 * u * .pi / 180 + tilt, torso = 0.24
        let hip = Vec2(c, 0.12)
        func rotate(_ dx: Double, _ dy: Double) -> Vec2 {
            Vec2(hip.x + dx * cos(tilt) - dy * sin(tilt), hip.y + dx * sin(tilt) + dy * cos(tilt))
        }
        let shoulder = Vec2(hip.x - torso * cos(phi), hip.y + torso * sin(phi))
        let head = Vec2(shoulder.x - 0.07 * cos(phi), shoulder.y + 0.07 * sin(phi) + 0.02)
        return [
            .nose: head,
            .leftShoulder: shoulder, .rightShoulder: Vec2(shoulder.x + 0.01, shoulder.y),
            .leftElbow: Vec2(head.x + 0.02, head.y + 0.05), .rightElbow: Vec2(head.x + 0.03, head.y + 0.05),
            .leftWrist: Vec2(head.x - 0.01, head.y), .rightWrist: Vec2(head.x, head.y),
            .leftHip: hip, .rightHip: Vec2(hip.x + 0.01, hip.y),
            .leftKnee: rotate(0.12, 0.12), .rightKnee: rotate(0.13, 0.12),
            .leftAnkle: rotate(0.22, 0.0), .rightAnkle: rotate(0.23, 0.0),
        ]
    }

    static func crunch(_ u: Double) -> Body { crunch(u, floor: 0) }

    /// Push-up side-on (left side to the camera): wrist fixed on the floor, elbow angle from
    /// 170° at the top to 85° at the bottom. u < 0 means standing upright.
    static func pushUp(_ u: Double) -> Body { pushUp(u, hips: 0) }

    /// `hips` moves the hips off the straight line: negative sags, positive piks.
    static func pushUp(_ u: Double, hips: Double) -> Body {
        if u < 0 { return squat(0) }
        let floorY = 0.12, wristX = 0.2, upper = 0.11, fore = 0.1
        let theta = (170 - 85 * u) * .pi / 180
        let reach = (upper * upper + fore * fore - 2 * upper * fore * cos(theta)).squareRoot()
        let shoulder = Vec2(wristX, floorY + reach)
        // Elbow: law of cosines for the angle at the wrist, bending back towards the feet.
        let atWrist = acos(max(-1, min(1, (fore * fore + reach * reach - upper * upper) / (2 * fore * reach))))
        let elbow = Vec2(wristX + fore * sin(atWrist), floorY + fore * cos(atWrist))
        let ankle = Vec2(shoulder.x + 0.5, floorY + 0.02)
        // A rigid plank: the hip on the shoulder–ankle line unless moved off it.
        let hip = Vec2((shoulder.x + ankle.x) / 2, (shoulder.y + ankle.y) / 2 + hips)
        return [
            .nose: Vec2(shoulder.x - 0.06, shoulder.y + 0.02),
            .leftShoulder: shoulder, .leftElbow: elbow, .leftWrist: Vec2(wristX, floorY),
            .leftHip: hip, .leftKnee: Vec2((hip.x + ankle.x) / 2, (hip.y + ankle.y) / 2), .leftAnkle: ankle,
        ]
    }
}
