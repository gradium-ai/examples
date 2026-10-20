import Foundation
import RepCoachCore

// Replays a pose recording from the phone through the same counting pipeline the app runs.
//
//   swift run repcoach-replay recording.jsonl [--exercise squat] [--rest 10] [--expect 10,10,8] [--trace]
//   swift run repcoach-replay recording.jsonl --stats
//   swift run repcoach-replay recording.jsonl --guide
//
// Prints every rep, partial rep and set as it happens, then the sets. With --expect, exits 1
// when the sets differ, so a recording of a bug becomes a regression check.

var args = Array(CommandLine.arguments.dropFirst())
@MainActor func option(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    defer { args.removeSubrange(i...(i + 1)) }
    return args[i + 1]
}
let exerciseName = option("--exercise")
let rest = option("--rest").flatMap(Double.init) ?? 10
// Which pose to count from: the image as captured ("normal"), or one of the rotated passes.
let view = option("--view") ?? "normal"
let expected = option("--expect").map { $0.split(separator: ",").compactMap { Int($0) } }
let trace = args.contains("--trace")
let statsOnly = args.contains("--stats")
// Prints the positioning directions the app would give, instead of counting.
let guideOnly = args.contains("--guide")
args.removeAll { $0 == "--trace" || $0 == "--stats" || $0 == "--guide" }

guard let path = args.first else {
    print("usage: repcoach-replay recording.jsonl [--exercise \(Exercise.allCases.map(\.rawValue).joined(separator: "|"))] [--rest 10] [--expect 10,10,8] [--view normal|left|right] [--trace] [--stats] [--guide]")
    exit(2)
}

if let exerciseName, Exercise(rawValue: exerciseName) == nil {
    print("unknown exercise \(exerciseName); one of \(Exercise.allCases.map(\.rawValue).joined(separator: ", "))")
    exit(2)
}
let data = try Data(contentsOf: URL(fileURLWithPath: path))
if statsOnly {
    printStats(try PoseRecording.decodeEntries(data))
    exit(0)
}
let (header, entries) = try PoseRecording.decodeEntries(data)
let frames: [PoseFrame] = entries.compactMap { entry in
    guard case let .frame(frame, extras) = entry else { return nil }
    if view == "normal" { return frame }
    // A rotated pass with nobody found is a frame with no joints, as the app records it.
    return extras.rotated[view] ?? PoseFrame(time: frame.time, aspect: 1 / frame.aspect, joints: [:])
}
let exercise = exerciseName.flatMap(Exercise.init(rawValue:)) ?? header.exercise
let start = frames.first?.time ?? 0
print("\(exercise.name), \(frames.count) frames over \(String(format: "%.1f", (frames.last?.time ?? 0) - start)) s, recorded \(header.recordedAt)")

if guideOnly {
    var last: Cue?
    for frame in frames {
        let g = Positioning.guidance(for: exercise, frame: frame.joints.isEmpty ? nil : frame)
        guard g.cue != last else { continue }
        last = g.cue
        let ratio = Positioning.facingRatio(frame).map { String(format: "  (facing ratio %.2f)", $0) } ?? ""
        print(String(format: "%7.2f  ", frame.time - start) + g.cue.text + ratio)
    }
    exit(0)
}

var pipeline = RepPipeline(exercise: exercise, restTimeout: rest, startTime: start)
for frame in frames {
    let t = String(format: "%7.2f", frame.time - start)
    for output in pipeline.process(frame) {
        switch output {
        case let .rep(set, number, duration):
            print("\(t)  set \(set) rep \(number)  (\(String(format: "%.1f", duration)) s)")
        case let .partial(depth):
            print("\(t)  partial rep, depth \(String(format: "%.2f", depth))")
        case let .setEnd(end):
            print("\(t)  set \(end.setNumber) \(end.discarded ? "discarded" : "done"): \(end.reps) reps")
            if !end.discarded { printFeedback(end.form, reps: end.reps) }
        case let .form(faults, say):
            let names = faults.map(\.label).sorted().joined(separator: ", ")
            let spoken = say.compactMap(\.live).joined(separator: " ")
            print("\(t)    form: \(names)" + (spoken.isEmpty ? "" : "  → says \"\(spoken)\""))
        }
    }
    if trace {
        let p = pipeline.counter.lastProgress.map { String(format: "%.2f", $0) } ?? "  - "
        let ref = pipeline.signal.restReference.map { String(format: "%.3f", $0) } ?? "-"
        print("\(t)  progress \(p)  phase \(pipeline.counter.phase)  rest-ref \(ref)")
    }
}
let summary = pipeline.finish(at: (frames.last?.time ?? 0) + rest + 1)
if let last = summary.sets.last, pipeline.tracker.completedSets.count == summary.sets.count, !pipeline.lastSetForm.isEmpty || last >= 3 {
    print("  last set:")
    printFeedback(pipeline.lastSetForm, reps: last)
}
print("sets: \(summary.sets)  total: \(summary.totalReps)")

/// The sentences the coach says about form after a set.
func printFeedback(_ faults: [FormFault], reps: Int) {
    for line in Coach.formFeedback(faults, reps: reps, exercise: exercise) { print("           \"\(line.text)\"") }
}

if let expected {
    if summary.sets == expected {
        print("as expected")
    } else {
        print("EXPECTED \(expected)")
        exit(1)
    }
}

// MARK: - Sensor statistics

/// What each sensor captured: how often a body was found, how confident each arm was in the
/// normal and the rotated images, how the phone was placed, and the AirPods sample rate.
func printStats(_ recording: (PoseRecording.Header, [PoseRecording.Entry])) {
    let (header, entries) = recording
    var frames: [(PoseFrame, PoseRecording.Extras)] = []
    var heads: [HeadMotion] = []
    for entry in entries {
        switch entry {
        case let .frame(f, e): frames.append((f, e))
        case let .head(h): heads.append(h)
        }
    }
    let times = frames.map(\.0.time) + heads.map(\.time)
    let span = (times.max() ?? 0) - (times.min() ?? 0)
    print("\(header.exercise.name), format v\(header.version ?? 1), \(String(format: "%.1f", span)) s, \(frames.count) pose frames, \(heads.count) AirPods samples")

    func pct(_ n: Int, _ d: Int) -> String { d == 0 ? "-" : String(format: "%3.0f%%", 100 * Double(n) / Double(d)) }
    func mean(_ xs: [Double]) -> String { xs.isEmpty ? "  -  " : String(format: "%.2f", xs.reduce(0, +) / Double(xs.count)) }

    print("\npose             body found   arm chain seen   left elbow conf   right elbow conf")
    let views: [(String, (PoseFrame, PoseRecording.Extras) -> PoseFrame?)] = [
        ("normal", { f, _ in f }),
        ("rotated left", { _, e in e.rotated["left"] }),
        ("rotated right", { _, e in e.rotated["right"] }),
    ]
    for (name, pick) in views {
        let poses = frames.compactMap { pick($0.0, $0.1) }
        guard !poses.isEmpty else { continue }
        let found = poses.filter { p in Joint.allCases.contains { p.sees($0) } }.count
        let arm = poses.filter { p in Side.allCases.contains { s in [s.shoulder, s.elbow, s.wrist].allSatisfy(p.sees) } }.count
        let left = poses.compactMap { $0.confidence[.leftElbow] }
        let right = poses.compactMap { $0.confidence[.rightElbow] }
        print(name.padding(toLength: 17, withPad: " ", startingAt: 0)
              + pct(found, frames.count).padding(toLength: 13, withPad: " ", startingAt: 0)
              + pct(arm, frames.count).padding(toLength: 17, withPad: " ", startingAt: 0)
              + mean(left).padding(toLength: 18, withPad: " ", startingAt: 0) + mean(right))
    }

    let gravities = frames.compactMap(\.1.gravity)
    if !gravities.isEmpty {
        let g = Vec3(gravities.map(\.x).reduce(0, +) / Double(gravities.count),
                     gravities.map(\.y).reduce(0, +) / Double(gravities.count),
                     gravities.map(\.z).reduce(0, +) / Double(gravities.count))
        let placement: String
        if abs(g.z) > 0.8 { placement = "lying flat" }
        else if abs(g.y) >= abs(g.x) { placement = g.y < 0 ? "portrait" : "portrait, upside down" }
        else { placement = g.x < 0 ? "landscape, home side right" : "landscape, home side left" }
        let tilt = asin(max(-1, min(1, -g.z))) * 180 / .pi
        print("\nphone: \(placement), screen tilted \(String(format: "%.0f", tilt))° from vertical, mean gravity (\(String(format: "%.2f, %.2f, %.2f", g.x, g.y, g.z)))")
    } else {
        print("\nphone: no gravity recorded")
    }

    if heads.count > 1 {
        let rate = Double(heads.count - 1) / (heads.last!.time - heads.first!.time)
        let sensors = Dictionary(grouping: heads, by: \.sensor).mapValues(\.count)
        // Vertical head acceleration: the user acceleration projected on gravity.
        let vertical = heads.map { h in
            let gl = (h.gravity.x * h.gravity.x + h.gravity.y * h.gravity.y + h.gravity.z * h.gravity.z).squareRoot()
            return gl > 0 ? -(h.userAcceleration.x * h.gravity.x + h.userAcceleration.y * h.gravity.y + h.userAcceleration.z * h.gravity.z) / gl : 0
        }
        let rms = (vertical.map { $0 * $0 }.reduce(0, +) / Double(vertical.count)).squareRoot()
        print("AirPods: \(String(format: "%.1f", rate)) Hz, sensors \(sensors), vertical head acceleration RMS \(String(format: "%.3f", rms)) g")
    } else {
        print("AirPods: no samples")
    }
}
