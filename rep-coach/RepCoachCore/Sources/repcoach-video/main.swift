import AVFoundation
import Foundation
import RepCoachCore
import Vision

// Runs Vision's body pose over a video file and writes a pose recording in the format the phone
// records, so repcoach-replay can count the reps in any video:
//
//   swift run repcoach-video clip.mp4 clip.jsonl [--exercise lunge] [--fps 15] [--rotated]
//
// Frames are sampled at --fps (the app runs pose at 15 per second, 10 with rotated passes).
// --rotated also records the image read a quarter turn left and right, as the app does for
// push-ups, so `repcoach-replay --view left|right` can count from those.

var args = Array(CommandLine.arguments.dropFirst())
@MainActor func option(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    defer { args.removeSubrange(i...(i + 1)) }
    return args[i + 1]
}
@MainActor func flag(_ name: String) -> Bool {
    defer { args.removeAll { $0 == name } }
    return args.contains(name)
}
let exerciseName = option("--exercise") ?? "squat"
let fps = option("--fps").flatMap(Double.init) ?? 15
let rotated = flag("--rotated")

guard args.count == 2, let exercise = Exercise(rawValue: exerciseName) else {
    print("usage: repcoach-video clip.mp4 out.jsonl [--exercise \(Exercise.allCases.map(\.rawValue).joined(separator: "|"))] [--fps 15] [--rotated]")
    exit(2)
}

let jointNames: [RepCoachCore.Joint: VNHumanBodyPoseObservation.JointName] = [
    .nose: .nose,
    .leftShoulder: .leftShoulder, .rightShoulder: .rightShoulder,
    .leftElbow: .leftElbow, .rightElbow: .rightElbow,
    .leftWrist: .leftWrist, .rightWrist: .rightWrist,
    .leftHip: .leftHip, .rightHip: .rightHip,
    .leftKnee: .leftKnee, .rightKnee: .rightKnee,
    .leftAnkle: .leftAnkle, .rightAnkle: .rightAnkle,
]

/// The most confident body in the image read in `orientation`, as the app's camera pipeline does.
func detect(_ buffer: CVPixelBuffer, _ orientation: CGImagePropertyOrientation, time: TimeInterval) -> PoseFrame? {
    let width = Double(CVPixelBufferGetWidth(buffer)), height = Double(CVPixelBufferGetHeight(buffer))
    let quarterTurn = orientation == .left || orientation == .right
    let aspect = quarterTurn ? height / width : width / height
    let request = VNDetectHumanBodyPoseRequest()
    try? VNImageRequestHandler(cvPixelBuffer: buffer, orientation: orientation).perform([request])
    guard let observation = request.results?.max(by: { $0.confidence < $1.confidence }),
          let points = try? observation.recognizedPoints(.all)
    else { return nil }
    var joints: [RepCoachCore.Joint: Vec2] = [:]
    var confidence: [RepCoachCore.Joint: Double] = [:]
    for (joint, name) in jointNames {
        guard let p = points[name], p.confidence > 0 else { continue }
        joints[joint] = Vec2(Double(p.location.x), Double(p.location.y))
        confidence[joint] = Double(p.confidence)
    }
    return joints.isEmpty ? nil : PoseFrame(time: time, aspect: aspect, joints: joints, confidence: confidence)
}

let asset = AVURLAsset(url: URL(fileURLWithPath: args[0]))
guard let track = try await asset.loadTracks(withMediaType: .video).first else {
    print("no video track in \(args[0])")
    exit(1)
}
let size = try await track.load(.naturalSize)
if try await track.load(.preferredTransform) != .identity {
    print("warning: the video is stored rotated; poses are read from the stored image")
}
let reader = try AVAssetReader(asset: asset)
let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
])
reader.add(output)
reader.startReading()

let out = URL(fileURLWithPath: args[1])
FileManager.default.createFile(atPath: out.path, contents: nil)
let file = try FileHandle(forWritingTo: out)
try file.write(contentsOf: PoseRecording.encode(PoseRecording.Header(
    exercise: exercise, aspect: Double(size.width / size.height), note: "from \(asset.url.lastPathComponent)")))

var next = 0.0, frames = 0, found = 0
while let sample = output.copyNextSampleBuffer() {
    let time = CMSampleBufferGetPresentationTimeStamp(sample).seconds
    guard time + 0.001 >= next, let buffer = CMSampleBufferGetImageBuffer(sample) else { continue }
    next = max(next + 1 / fps, time)
    let pose = detect(buffer, .up, time: time)
    var extras = PoseRecording.Extras()
    if rotated {
        extras.rotated["left"] = detect(buffer, .left, time: time)
        extras.rotated["right"] = detect(buffer, .right, time: time)
    }
    let aspect = Double(CVPixelBufferGetWidth(buffer)) / Double(CVPixelBufferGetHeight(buffer))
    try file.write(contentsOf: PoseRecording.encode(pose ?? PoseFrame(time: time, aspect: aspect, joints: [:]), extras: extras))
    frames += 1
    if pose != nil { found += 1 }
}
try file.close()
if reader.status == .failed { print("read failed: \(reader.error?.localizedDescription ?? "?")") }
print("\(frames) frames, a body in \(found) (\(frames > 0 ? 100 * found / frames : 0)%), \(Int(size.width))×\(Int(size.height)) → \(out.lastPathComponent)")
