import Foundation
import Observation
import QuartzCore
import RepCoachCore
import SwiftData
import UIKit

/// One exercise session: camera in, counts out loud, sets on screen, a record at the end.
@MainActor
@Observable
final class WorkoutModel {
    enum Phase: Equatable {
        /// Camera on, placement guide shown, nothing counted yet.
        case setup
        case active
        case finished(WorkoutSummary)
    }

    let exercise: Exercise
    var target: Int
    private(set) var phase: Phase = .setup

    private(set) var frame: PoseFrame?
    private(set) var framingProblem: String? = "Step into view"
    private(set) var progress: Double?
    private(set) var setNumber = 1
    private(set) var repsInSet = 0
    private(set) var completedSets: [Int] = []
    private(set) var restRemaining: TimeInterval?
    private(set) var lastRepDuration: TimeInterval?
    /// Shown briefly after a rep that did not reach full depth.
    private(set) var hint: String?
    /// A form fault in the rep just counted: shown in red on the body for a moment.
    private(set) var formAlert: FormFault?
    /// What the coach said about the last set's form, shown while resting.
    private(set) var setFeedback: (set: Int, lines: [String])?
    /// Form advice across the workout, for the summary: up to three, most recent first.
    private(set) var workoutFeedback: [String] = []
    private var formAlertClear: Task<Void, Never>?
    private(set) var heartbeat: CameraPipeline.Heartbeat?
    private(set) var cameraDenied = false
    /// Set when frames stop arriving: a wedged camera must be visible, not silent.
    private(set) var cameraStalled = false
    private(set) var recordingName: String?
    private(set) var airPods: MotionSensors.AirPods = .disconnected
    /// AirPods samples per second over the last second.
    private(set) var headRate: Double = 0
    /// How the phone is standing, from its gravity vector.
    private(set) var placement: String?
    /// Directions for getting into position, while setting up.
    private(set) var guidance: Guidance?
    /// 3, 2, 1 while counting down to starting on its own.
    private(set) var countdown: Int?

    let camera = CameraPipeline()
    private let sensors = MotionSensors()
    private var headSamples = 0
    private var headRateWindowStart = CACurrentMediaTime()
    private var lastHeadSample: TimeInterval?
    private let voice: VoiceCoach
    private var pipeline: RepPipeline
    private var coach: Coach
    private var recorder: PoseRecorder?
    private var ticker: Task<Void, Never>?
    private var hintClear: Task<Void, Never>?
    private var lastCallback = CACurrentMediaTime()
    private var guidanceFilter = GuidanceFilter()
    private var spokenCue: Cue?
    private var spokenAt: TimeInterval = 0
    private var countdownTask: Task<Void, Never>?
    /// Mid-workout, a turn the wrong way (facing the phone for lunges) is said once it lasts.
    private var turnFilter = GuidanceFilter(hold: 1.5)
    private var spokenTurn: Cue?
    private(set) var startedAt = Date()

    var restTimeout: TimeInterval {
        let saved = UserDefaults.standard.double(forKey: Settings.restTimeoutKey)
        return saved > 0 ? saved : 10
    }

    private var motivation: Bool {
        UserDefaults.standard.object(forKey: Settings.motivationKey) as? Bool ?? true
    }

    var autoStart: Bool {
        UserDefaults.standard.object(forKey: Settings.autoStartKey) as? Bool ?? true
    }

    private var recordPoses: Bool {
        UserDefaults.standard.bool(forKey: Settings.recordPosesKey)
    }

    init(exercise: Exercise, target: Int, voice: VoiceCoach) {
        self.exercise = exercise
        self.target = target
        self.voice = voice
        pipeline = RepPipeline(exercise: exercise)
        coach = Coach(target: target, motivation: true)
    }

    func appear() async {
        UIApplication.shared.isIdleTimerDisabled = true
        guard await CameraPipeline.requestAccess() else {
            cameraDenied = true
            return
        }
        camera.setHandlers(
            onPose: { [weak self] output in Task { @MainActor in self?.handle(output) } },
            onHeartbeat: { [weak self] beat in Task { @MainActor in self?.heartbeat = beat } })
        camera.start()
        // Motion only goes into recordings, so it (and its permission prompt) stays off otherwise.
        // Delivered on the main queue, so straight into the model with no hop.
        if recordPoses {
            sensors.onHead = { [weak self] sample in self?.handle(sample) }
            sensors.onState = { [weak self] state in self?.airPods = state }
            sensors.start()
        }
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self else { return }
                self.tick()
            }
        }
    }

    func disappear() {
        UIApplication.shared.isIdleTimerDisabled = false
        ticker?.cancel()
        ticker = nil
        camera.setHandlers(onPose: nil, onHeartbeat: nil)
        camera.setRotatedPasses(false)
        camera.stop()
        sensors.stop()
        cancelCountdown()
        recorder?.close()
        recorder = nil
        if phase == .active { voice.interrupt() }
    }

    /// Starts counting. `announce` is said first: the countdown ends on "Go!".
    func start(announce: String = PhraseBook.ready) {
        guard phase == .setup else { return }
        cancelCountdown()
        guidance = nil
        let now = CACurrentMediaTime()
        pipeline = RepPipeline(exercise: exercise, restTimeout: restTimeout, startTime: now)
        coach = Coach(target: target, motivation: motivation)
        setNumber = 1
        repsInSet = 0
        completedSets = []
        lastRepDuration = nil
        startedAt = Date()
        if recordPoses {
            recorder = PoseRecorder(exercise: exercise, aspect: CameraPipeline.imageAspect)
            recordingName = recorder?.url.lastPathComponent
            // Push-ups are where a horizontal body trips Vision up: record the rotated views too.
            camera.setRotatedPasses(exercise == .pushUp && recorder != nil)
        }
        phase = .active
        voice.say(Utterance(announce, precomputed: true))
    }

    func finish(saveTo context: ModelContext) {
        guard phase == .active else { return }
        let setsBefore = completedSets.count
        let summary = pipeline.finish(at: CACurrentMediaTime())
        recorder?.close()
        recorder = nil
        camera.setRotatedPasses(false)
        completedSets = summary.sets
        repsInSet = 0
        restRemaining = nil
        setFeedback = nil
        // The set that Finish closed gets its form advice too, after the totals.
        let lastSet = summary.sets.count > setsBefore ? summary.sets.last : nil
        let feedback = lastSet.map { Coach.formFeedback(pipeline.lastSetForm, reps: $0, exercise: exercise) } ?? []
        remember(pipeline.lastSetForm)
        voice.say([coach.summary(summary)] + feedback)
        if !summary.sets.isEmpty {
            context.insert(WorkoutRecord(date: startedAt, exercise: exercise, target: target,
                                         duration: summary.duration, sets: summary.sets))
            try? context.save()
        }
        phase = .finished(summary)
    }

    // MARK: - Frames

    private func handle(_ output: CameraPipeline.Output) {
        let frame = output.pose
        lastCallback = CACurrentMediaTime()
        cameraStalled = false
        self.frame = frame
        framingProblem = exercise.framingProblem(frame)
        if phase == .setup { guide(frame, at: output.time) }
        if phase == .active { checkTurn(frame, at: output.time) }
        guard phase == .active else {
            progress = nil
            return
        }
        // Frames with nobody in view are recorded too (as no joints), so a replay sees exactly
        // what the counter saw.
        recorder?.write(frame ?? PoseFrame(time: output.time, aspect: CameraPipeline.imageAspect, joints: [:]),
                        extras: PoseRecording.Extras(gravity: sensors.gravity, rotated: output.rotated))
        let outputs = frame.map { pipeline.process($0) } ?? pipeline.missing(at: output.time)
        // The count first, then (once per workout per fault) what to fix, in one go.
        var lines: [Utterance] = []
        for output in outputs {
            switch output {
            case let .rep(set, number, duration):
                setNumber = set
                repsInSet = number
                lastRepDuration = duration
                setFeedback = nil
                lines += coach.rep(number)
            case let .partial(depth):
                show(hint: depth > 0.6 ? "Almost: go a bit further" : "Go all the way")
            case let .setEnd(end):
                setEnded(end)
            case let .form(faults, say):
                show(alert: FormFault.allCases.first(where: faults.contains))
                lines += say.compactMap(\.live).map { Utterance($0, precomputed: true) }
            }
        }
        if !lines.isEmpty { voice.say(lines) }
        progress = pipeline.counter.lastProgress
    }

    // MARK: - Getting into position

    private func guide(_ frame: PoseFrame?, at time: TimeInterval) {
        let shown = guidanceFilter.update(Positioning.guidance(for: exercise, frame: frame), at: time)
        guidance = shown
        guard let cue = shown?.cue else { return }
        if cue == .ready {
            if autoStart, countdownTask == nil, guidanceFilter.held(at: time) >= 0.8 { beginCountdown() }
        } else if countdownTask != nil {
            cancelCountdown()
        }
        // Each new direction is said once it is steady, and again every few seconds while it
        // still applies, for someone who missed it walking into place.
        if countdownTask == nil, cue != spokenCue || (cue != .ready && time - spokenAt > 6) {
            spokenCue = cue
            spokenAt = time
            voice.say(Utterance(cue.text, precomputed: true))
        }
    }

    /// Facing the wrong way mid-workout, reps stop counting without a word: say so, once.
    private func checkTurn(_ frame: PoseFrame?, at time: TimeInterval) {
        guard let frame else { return }
        let cue = turnFilter.update(Guidance(cue: exercise.turn(frame) ?? .ready), at: time)?.cue
        guard cue != spokenTurn else { return }
        spokenTurn = cue
        if let cue, cue != .ready { voice.say(Utterance(cue.text, precomputed: true)) }
    }

    private func beginCountdown() {
        countdownTask = Task { [weak self] in
            for n in [3, 2, 1] {
                guard let self, !Task.isCancelled else { return }
                self.countdown = n
                self.voice.say(Utterance(PhraseBook.count(n), precomputed: true))
                try? await Task.sleep(for: .seconds(1))
            }
            guard let self, !Task.isCancelled else { return }
            self.start(announce: PhraseBook.go)
        }
    }

    private func cancelCountdown() {
        countdownTask?.cancel()
        countdownTask = nil
        countdown = nil
    }

    private func handle(_ sample: HeadMotion) {
        headSamples += 1
        lastHeadSample = CACurrentMediaTime()
        if phase == .active { recorder?.write(sample) }
    }

    private func tick() {
        let now = CACurrentMediaTime()
        if now - lastCallback > 3 { cameraStalled = true }
        if now - headRateWindowStart >= 1 {
            headRate = Double(headSamples) / (now - headRateWindowStart)
            headSamples = 0
            headRateWindowStart = now
        }
        // Samples stop while the AirPods are out of the ears, without a disconnect.
        if airPods == .streaming, let last = lastHeadSample, now - last > 2 { airPods = .connected }
        if airPods == .connected, let last = lastHeadSample, now - last < 0.5 { airPods = .streaming }
        placement = sensors.gravity.map(Self.placement)
        guard phase == .active else { return }
        if let end = pipeline.tick(at: now) { setEnded(end) }
        restRemaining = pipeline.tracker.restRemaining(at: now)
    }

    private func setEnded(_ end: SetEnd) {
        repsInSet = 0
        setNumber = pipeline.tracker.setNumber
        restRemaining = nil
        guard !end.discarded else { return }
        completedSets = pipeline.tracker.completedSets
        let feedback = Coach.formFeedback(end.form, reps: end.reps, exercise: exercise)
        setFeedback = feedback.isEmpty ? nil : (end.setNumber, feedback.map(\.text))
        remember(end.form)
        voice.say((coach.setEnded(end).map { [$0] } ?? []) + feedback)
    }

    /// Keeps the advice for the summary: the latest first, no repeats, at most three.
    private func remember(_ faults: [FormFault]) {
        let advice = faults.map { $0.advice(for: exercise) }
        workoutFeedback = Array((advice + workoutFeedback.filter { !advice.contains($0) }).prefix(3))
    }

    private func show(alert fault: FormFault?) {
        guard let fault else { return }
        formAlert = fault
        formAlertClear?.cancel()
        formAlertClear = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            if !Task.isCancelled { self?.formAlert = nil }
        }
    }

    private static func placement(_ g: Vec3) -> String {
        if abs(g.z) > 0.8 { return "lying flat" }
        if abs(g.y) >= abs(g.x) { return g.y < 0 ? "portrait" : "upside down" }
        return "landscape"
    }

    private func show(hint text: String) {
        hint = text
        hintClear?.cancel()
        hintClear = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            if !Task.isCancelled { self?.hint = nil }
        }
    }
}
