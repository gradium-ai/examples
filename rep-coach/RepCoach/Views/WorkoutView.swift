import RepCoachCore
import SwiftData
import SwiftUI

/// The camera, full screen, with the count and a few stats laid over it: no panels, only
/// type on gradients, so the person on screen stays the picture.
struct WorkoutView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var model: WorkoutModel
    /// Shows "+1" next to the count for a moment after each rep.
    @State private var plusOne = false
    private let voice: VoiceCoach

    init(exercise: Exercise, voice: VoiceCoach) {
        self.voice = voice
        _model = State(initialValue: WorkoutModel(exercise: exercise, target: Settings.target(for: exercise), voice: voice))
    }

    private var framed: Bool { model.framingProblem == nil }

    private var summary: WorkoutSummary? {
        if case let .finished(summary) = model.phase { return summary }
        return nil
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            CameraPreview(session: model.camera.session)
                .ignoresSafeArea()
            if summary == nil {
                SkeletonOverlay(frame: model.frame, color: framed ? Theme.accent : Theme.warning,
                                alert: model.formAlert?.bones ?? [])
                    .ignoresSafeArea()
            }
            Scrim(dimmed: summary != nil)
                .ignoresSafeArea()
            if model.phase == .setup, let edges = model.guidance?.edges, !edges.isEmpty {
                EdgeGlow(edges: edges)
                    .ignoresSafeArea()
                    .transition(.opacity)
            }

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    header
                    Spacer(minLength: 12)
                    status
                }
                Spacer()
                notice
                Spacer()
                bottom
            }
            .padding(.horizontal, 24)
            .padding(.top, 4)
            .padding(.bottom, 8)
        }
        .preferredColorScheme(.dark)
        .toolbar(.hidden, for: .navigationBar)
        .animation(.easeOut(duration: 0.25), value: model.phase)
        .animation(.easeOut(duration: 0.2), value: model.hint)
        .animation(.easeOut(duration: 0.2), value: model.formAlert)
        .animation(.easeOut(duration: 0.2), value: model.framingProblem)
        .animation(.easeOut(duration: 0.25), value: model.guidance?.cue)
        .animation(.easeOut(duration: 0.25), value: model.guidance?.edges)
        .animation(.snappy, value: model.countdown)
        .onChange(of: model.repsInSet) { old, new in
            guard new > old else { return }
            plusOne = true
            Task {
                try? await Task.sleep(for: .milliseconds(500))
                withAnimation(.easeOut(duration: 0.6)) { plusOne = false }
            }
        }
        .task { await model.appear() }
        .onDisappear { model.disappear() }
    }

    // MARK: - Top

    /// "SQUAT · SET 2", the big number, and what it counts.
    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(model.exercise.name) · \(stage)")
                .eyebrow()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            HStack(alignment: .top, spacing: 10) {
                Text(String(format: "%02d", bigNumber))
                    .font(.system(size: 112, weight: .bold).width(.compressed))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(bigNumber)))
                    .animation(.snappy, value: bigNumber)
                    .shadow(color: .black.opacity(0.35), radius: 10)
                    // The compressed digits sit in a tall line box: pull the captions in.
                    .padding(.top, -4)
                    .padding(.bottom, -16)
                if model.phase == .setup {
                    targetStepper.padding(.top, 22)
                } else if model.phase == .active {
                    Text("+1")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .padding(.top, 30)
                        .opacity(plusOne ? 1 : 0)
                        .offset(y: plusOne ? 0 : -8)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityCount)
            Text(caption)
                .eyebrow()
            if let fault = model.formAlert {
                Label(fault.label, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(.red, in: Capsule())
                    .padding(.top, 10)
                    .transition(.opacity)
            } else if let hint = model.hint {
                Label(hint, systemImage: "exclamationmark.circle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.warning)
                    .padding(.top, 10)
                    .transition(.opacity)
            }
        }
    }

    private var stage: String {
        switch model.phase {
        case .setup: "Setup"
        case .active: "Set \(model.setNumber)"
        case .finished: "Done"
        }
    }

    private var bigNumber: Int {
        switch model.phase {
        case .setup: model.target
        case .active: model.repsInSet
        case let .finished(summary): summary.totalReps
        }
    }

    private var caption: String {
        switch model.phase {
        case .setup:
            return "Reps per set"
        case .active:
            return "of \(model.target) reps"
        case let .finished(summary):
            let sets = summary.sets.count
            return "Reps in \(sets) \(sets == 1 ? "set" : "sets")"
        }
    }

    private var accessibilityCount: String {
        switch model.phase {
        case .setup: "Target \(model.target) reps per set"
        case .active: "\(model.repsInSet) of \(model.target) reps"
        case let .finished(summary): "\(summary.totalReps) reps"
        }
    }

    private var targetStepper: some View {
        VStack(spacing: 8) {
            RoundButton(symbol: "plus", label: "More reps") { setTarget(model.target + 1) }
                .disabled(model.target >= 50)
            RoundButton(symbol: "minus", label: "Fewer reps") { setTarget(model.target - 1) }
                .disabled(model.target <= 1)
        }
    }

    private func setTarget(_ value: Int) {
        model.target = min(max(value, 1), 50)
        UserDefaults.standard.set(model.target, forKey: Settings.targetKey(model.exercise))
    }

    /// Framing at a glance, then the quieter things: AirPods, voice, recording.
    private var status: some View {
        VStack(alignment: .trailing, spacing: 10) {
            HStack(spacing: 8) {
                StatusPill(text: statusText, color: statusColor)
                if model.phase != .active {
                    RoundButton(symbol: "xmark", label: "Close") { dismiss() }
                }
            }
            VStack(alignment: .trailing, spacing: 4) {
                if model.airPods != .disconnected {
                    Text(model.airPods == .streaming ? "AirPods \(Int(model.headRate.rounded())) Hz" : model.airPods.label)
                        .foregroundStyle(model.airPods == .streaming ? Theme.accent : .white.opacity(0.6))
                }
                if voice.status != .ready {
                    Text(voice.status == .idle ? "Voice off" : "System voice")
                }
                if model.recordingName != nil, model.phase == .active {
                    Text("● Rec").foregroundStyle(.red)
                    // What each sensor is delivering, to catch a dead one at the gym.
                    Text(sensorReadout).monospacedDigit()
                }
            }
            .font(.caption2.weight(.semibold))
            .textCase(.uppercase)
            .tracking(1)
            .foregroundStyle(.white.opacity(0.6))
        }
    }

    private var statusText: String {
        if model.cameraDenied || model.cameraStalled { return "No camera" }
        if model.phase == .setup { return model.guidance?.cue == .ready ? "In position" : "Adjust" }
        return framed ? "In frame" : "Adjust"
    }

    private var statusColor: Color {
        if model.cameraDenied || model.cameraStalled { return Theme.warning }
        if model.phase == .setup { return model.guidance?.cue == .ready ? Theme.accent : Theme.warning }
        return framed ? Theme.accent : Theme.warning
    }

    private var sensorReadout: String {
        let camera = model.heartbeat.map { "cam \(Int($0.cameraFPS.rounded())) · pose \(Int($0.poseFPS.rounded()))" } ?? "cam –"
        return "\(camera) · \(model.placement ?? "–")"
    }

    // MARK: - Middle

    /// What to fix, when something needs fixing. While setting up, live directions into
    /// position and then the countdown.
    @ViewBuilder
    private var notice: some View {
        if model.phase == .setup, !model.cameraDenied, !model.cameraStalled {
            if let n = model.countdown {
                Countdown(number: n)
                    .frame(maxWidth: .infinity)
            } else if let guidance = model.guidance {
                GuidanceCard(guidance: guidance, symbol: symbol(for: guidance))
                    .frame(maxWidth: .infinity)
                    .id(guidance.cue)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        } else if let message = noticeText, summary == nil {
            Text(message)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(.black)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Theme.warning, in: Capsule())
                .frame(maxWidth: .infinity)
                .transition(.opacity)
        }
    }

    private func symbol(for guidance: Guidance) -> String {
        switch guidance.cue {
        case .stepIntoView: "figure.walk"
        case .stepBack: "arrow.down.right.and.arrow.up.left"
        case .comeCloser: "arrow.up.left.and.arrow.down.right"
        case .move: guidance.direction == .left ? "arrow.left" : "arrow.right"
        case .faceThePhone: "arrow.uturn.left"
        case .turnSideways: "arrow.turn.up.right"
        case .lieDown: model.exercise.symbol
        case .cantSee: "eye.slash"
        case .ready: "checkmark"
        }
    }

    private var noticeText: String? {
        if model.cameraDenied { return "Camera access is off: allow it in Settings" }
        if model.cameraStalled { return "The camera stopped sending frames" }
        return model.framingProblem
    }

    // MARK: - Bottom

    @ViewBuilder
    private var bottom: some View {
        switch model.phase {
        case .setup: setupSection
        case .active: activeSection
        case let .finished(summary): finishedSection(summary)
        }
    }

    private var setupSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Placement").eyebrow()
                Text(model.exercise.placement.headline)
                    .font(.title3.weight(.semibold))
            }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(model.exercise.placement.steps.enumerated()), id: \.offset) { i, step in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(String(format: "%02d", i + 1))
                            .font(.caption.weight(.bold).monospacedDigit())
                            .foregroundStyle(Theme.accent)
                        Text(step)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
            }
            if model.autoStart {
                HStack {
                    Label("Starts on its own once you're in position", systemImage: "figure.stand")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))
                    Spacer()
                    Button("Start now") { model.start() }
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(Theme.accent)
                        .disabled(model.cameraDenied)
                }
                .padding(.top, 8)
            } else {
                PrimaryButton(title: framed ? "Start" : "Start anyway") { model.start() }
                    .disabled(model.cameraDenied)
                    .padding(.top, 8)
            }
        }
    }

    private var activeSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let feedback = model.setFeedback {
                FeedbackList(title: "Set \(feedback.set) form", lines: feedback.lines)
                    .transition(.opacity)
            }
            HStack(alignment: .firstTextBaseline) {
                Text("This set").eyebrow()
                Spacer()
                if let rest = restText {
                    Text(rest)
                        .font(.footnote.weight(.bold).monospacedDigit())
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.accent)
                        .transition(.opacity)
                }
            }
            RepTrack(done: model.repsInSet, target: model.target, live: model.progress)
            HStack(alignment: .bottom) {
                Stat(label: "Earlier sets", value: model.completedSets.isEmpty ? "–" : model.completedSets.map(String.init).joined(separator: " · "))
                Spacer()
                Stat(label: "Last rep", value: model.lastRepDuration.map { String(format: "%.1fs", $0) } ?? "–")
                Spacer()
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    Stat(label: "Time", value: clock(timeline.date.timeIntervalSince(model.startedAt)), alignment: .trailing)
                }
            }
            .padding(.top, 6)
            Button {
                model.finish(saveTo: context)
            } label: {
                Label("Finish", systemImage: "stop.fill")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .background(.white.opacity(0.14), in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
        }
        .animation(.easeOut(duration: 0.2), value: restText)
    }

    /// The countdown runs between every rep: only call it rest once the pause is real.
    private var restText: String? {
        guard let remaining = model.restRemaining, model.restTimeout - remaining > 2 else { return nil }
        return "Rest · set ends in \(Int(remaining.rounded(.up)))"
    }

    private func finishedSection(_ summary: WorkoutSummary) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            if summary.sets.isEmpty {
                Text("No full sets were counted.")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.8))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 28) {
                        ForEach(Array(summary.sets.enumerated()), id: \.offset) { i, reps in
                            Stat(label: "Set \(i + 1)", value: "\(reps)")
                        }
                    }
                }
                Rectangle()
                    .fill(.white.opacity(0.15))
                    .frame(height: 1)
                HStack(alignment: .bottom) {
                    Stat(label: "Best set", value: "\(summary.sets.max() ?? 0)")
                    Spacer()
                    Stat(label: "Target", value: "\(model.target)")
                    Spacer()
                    Stat(label: "Time", value: clock(summary.duration), alignment: .trailing)
                }
            }
            if !model.workoutFeedback.isEmpty {
                FeedbackList(title: "Form", lines: model.workoutFeedback)
            }
            PrimaryButton(title: "Done") { dismiss() }
                .padding(.top, 8)
        }
    }

    private func clock(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}

// MARK: - Pieces

private extension View {
    /// Small spaced capitals, for labels.
    func eyebrow() -> some View {
        font(.footnote.weight(.semibold))
            .textCase(.uppercase)
            .tracking(1.5)
            .foregroundStyle(.white.opacity(0.75))
    }
}

/// The coach's form advice, as it was said.
private struct FeedbackList: View {
    let title: String
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).eyebrow()
            ForEach(lines, id: \.self) { line in
                Label(line, systemImage: "figure.strengthtraining.traditional")
                    .labelStyle(FeedbackLabelStyle())
            }
        }
    }
}

private struct FeedbackLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle().fill(Theme.accent).frame(width: 6, height: 6).alignmentGuide(.firstTextBaseline) { $0[.bottom] + 1 }
            configuration.title
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.9))
        }
    }
}

/// One direction, big enough to read from a few metres away, with its arrow moving the way to go.
private struct GuidanceCard: View {
    let guidance: Guidance
    let symbol: String

    private var ready: Bool { guidance.cue == .ready }

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 64, weight: .bold))
                .foregroundStyle(ready ? .black : Theme.warning)
                .frame(width: 112, height: 112)
                .background(ready ? Theme.accent : .black.opacity(0.55), in: Circle())
                .overlay(Circle().strokeBorder(ready ? .clear : Theme.warning.opacity(0.6), lineWidth: 2))
                .symbolEffect(.bounce, options: ready ? .nonRepeating : .repeat(.periodic(delay: 0.6)), value: guidance.cue)
            Text(guidance.cue.text.replacingOccurrences(of: ".", with: ""))
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
                .shadow(color: .black.opacity(0.6), radius: 8)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The 3, 2, 1 before the workout starts on its own.
private struct Countdown: View {
    let number: Int
    @State private var fill = 0.0

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.2), lineWidth: 8)
            Circle()
                .trim(from: 0, to: fill)
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(number)")
                .font(.system(size: 96, weight: .bold).width(.compressed))
                .contentTransition(.numericText(countsDown: true))
        }
        .frame(width: 170, height: 170)
        .shadow(color: .black.opacity(0.4), radius: 12)
        .onAppear { animate() }
        .onChange(of: number) { _, _ in animate() }
        .accessibilityLabel("Starting in \(number)")
    }

    private func animate() {
        fill = 0
        withAnimation(.linear(duration: 1)) { fill = 1 }
    }
}

/// A warm glow along the edges of the picture the body runs off.
private struct EdgeGlow: View {
    let edges: Set<PictureEdge>

    var body: some View {
        ZStack {
            ForEach(Array(edges), id: \.self) { edge in
                LinearGradient(colors: [Theme.warning.opacity(0.7), .clear], startPoint: start(edge), endPoint: end(edge))
                    .frame(width: edge == .left || edge == .right ? 70 : nil, height: edge == .top || edge == .bottom ? 70 : nil)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment(edge))
            }
        }
        .allowsHitTesting(false)
    }

    private func alignment(_ e: PictureEdge) -> Alignment {
        switch e { case .top: .top; case .bottom: .bottom; case .left: .leading; case .right: .trailing }
    }
    private func start(_ e: PictureEdge) -> UnitPoint {
        switch e { case .top: .top; case .bottom: .bottom; case .left: .leading; case .right: .trailing }
    }
    private func end(_ e: PictureEdge) -> UnitPoint {
        switch e { case .top: .bottom; case .bottom: .top; case .left: .trailing; case .right: .leading }
    }
}

/// Darkens the top and bottom of the camera so the type reads on any background.
private struct Scrim: View {
    let dimmed: Bool

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                LinearGradient(colors: [.black.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 300)
                Spacer()
                LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 440)
            }
            if dimmed { Color.black.opacity(0.5).transition(.opacity) }
        }
        .allowsHitTesting(false)
    }
}

private struct StatusPill: View {
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 7) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text)
                .font(.footnote.weight(.semibold))
                .textCase(.uppercase)
                .tracking(0.5)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.black.opacity(0.45), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
    }
}

private struct RoundButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.bold))
                .frame(width: 36, height: 36)
                .background(.black.opacity(0.45), in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

private struct PrimaryButton: View {
    let title: String
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(Theme.accent.opacity(enabled ? 1 : 0.35), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct Stat: View {
    let label: String
    let value: String
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(label).eyebrow()
            Text(value)
                .font(.system(size: 30, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
    }
}

/// One segment per rep of the target: counted reps filled, and the next one filling live
/// with how deep into it you are. Reps past the target add segments.
private struct RepTrack: View {
    let done: Int
    let target: Int
    let live: Double?

    private var count: Int { max(target, done) }

    var body: some View {
        HStack(spacing: count > 20 ? 3 : 5) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(.white.opacity(0.18))
                    .overlay(alignment: .leading) {
                        GeometryReader { geo in
                            Capsule()
                                .fill(i < done ? Theme.accent : .white.opacity(0.85))
                                .frame(width: geo.size.width * fill(i))
                        }
                    }
            }
        }
        .frame(height: 8)
        .animation(.linear(duration: 0.07), value: live)
        .animation(.snappy, value: done)
        .accessibilityHidden(true)
    }

    private func fill(_ i: Int) -> Double {
        if i < done { return 1 }
        if i == done { return min(max(live ?? 0, 0), 1) }
        return 0
    }
}
