import Foundation

public enum Exercise: String, CaseIterable, Codable, Sendable, Identifiable {
    case squat
    case pullUp
    case latPulldown
    case pushUp
    case armRaise
    case lunge
    case romanianDeadlift
    case crunch

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .squat: "Squat"
        case .pullUp: "Pull-up"
        case .latPulldown: "Lat pulldown"
        case .pushUp: "Push-up"
        case .armRaise: "Arm raise"
        case .lunge: "Lunge"
        case .romanianDeadlift: "Romanian deadlift"
        case .crunch: "Crunch"
        }
    }

    /// Lower-case plural, as spoken: "three sets of squats".
    public var plural: String {
        switch self {
        case .squat: "squats"
        case .pullUp: "pull-ups"
        case .latPulldown: "lat pulldowns"
        case .pushUp: "push-ups"
        case .armRaise: "arm raises"
        case .lunge: "lunges"
        case .romanianDeadlift: "Romanian deadlifts"
        case .crunch: "crunches"
        }
    }

    /// An SF Symbol for the exercise.
    public var symbol: String {
        switch self {
        case .squat: "figure.cross.training"
        case .pullUp: "figure.climbing"
        case .latPulldown: "figure.rower"
        case .pushUp: "figure.core.training"
        case .armRaise: "figure.arms.open"
        case .lunge: "figure.strengthtraining.functional"
        case .romanianDeadlift: "figure.strengthtraining.traditional"
        case .crunch: "figure.pilates"
        }
    }

    public var defaultTarget: Int {
        switch self {
        case .squat: 10
        case .pullUp: 8
        case .latPulldown: 12
        case .pushUp: 15
        case .armRaise: 10
        case .lunge: 12
        case .romanianDeadlift: 10
        case .crunch: 15
        }
    }

    /// When a rep is counted. Pull-ups, pulldowns and crunches count at the hardest point (chin
    /// over the bar, bar at the chest, shoulders curled up), where people count them aloud; the
    /// body must return before the next one can count. The rest count back at the start.
    public var countsAt: CountPoint {
        switch self {
        case .pullUp, .latPulldown, .crunch: .peak
        case .squat, .pushUp, .armRaise, .lunge, .romanianDeadlift: .completion
        }
    }

    public var thresholds: RepThresholds {
        switch self {
        // Hip down to about a fifth of its standing height above the knee: just above parallel.
        case .squat: RepThresholds(peak: 0.78, rest: 0.25)
        // Nose within a few centimetres of the hands, i.e. chin at or over the bar.
        case .pullUp: RepThresholds(peak: 0.92, rest: 0.25)
        // Hands down to about chin height.
        case .latPulldown: RepThresholds(peak: 0.85, rest: 0.25)
        // Elbows past about 104°, back up past about 140°.
        case .pushUp: RepThresholds(peak: 0.85, rest: 0.25)
        // Both hands well above the head; back down with the hands below the chest.
        case .armRaise: RepThresholds(peak: 0.85, rest: 0.25)
        // Front thigh down to well under half its standing height above the knee: real lunges
        // bottom out around 0.7, as the thigh rarely gets quite level.
        case .lunge: RepThresholds(peak: 0.55, rest: 0.3, confirmFrames: 3, minimumRepDuration: 0.6)
        // Torso tipped past about 45° from upright; back up within about 25°.
        case .romanianDeadlift: RepThresholds(peak: 0.7, rest: 0.25)
        // Shoulders curled up about 11° off the floor; back down within about 4°.
        case .crunch: RepThresholds(peak: 0.75, rest: 0.3, started: 0.45)
        }
    }

    /// Where to put the phone, shown before the set.
    public var placement: Placement {
        switch self {
        case .squat:
            Placement(
                headline: "Phone in front, at hip height",
                steps: ["Prop the phone upright 2–3 m in front of the Smith machine, about hip height.",
                        "Face it. Head, hips and knees must stay in view at the bottom of the squat.",
                        "Side-on works too."])
        case .pullUp:
            Placement(
                headline: "Phone low, tilted up at the bar",
                steps: ["Lean the phone against a bench or bag 2–3 m in front of the bar, tilted up.",
                        "Your hands on the bar and your face must be in view while you hang.",
                        "Hang still for a second before the first rep."])
        case .latPulldown:
            Placement(
                headline: "Phone at seat height, seeing the bar",
                steps: ["Stand the phone 1.5–2.5 m in front of or behind the machine, at seat height.",
                        "Tilt it up until your hands on the bar are in view with arms straight.",
                        "Start with arms fully up."])
        case .pushUp:
            Placement(
                headline: "Phone on the floor, to your side",
                steps: ["Stand the phone upright on the floor 2.5–3 m to your side.",
                        "Your whole body, side-on, must fit in the frame.",
                        "Start at the top, arms straight."])
        case .armRaise:
            Placement(
                headline: "Phone at chest height, facing you",
                steps: ["Stand the phone upright at chest height, 2–2.5 m away.",
                        "Your hips and both hands raised overhead must be in view.",
                        "Arms down by your sides, out to a T, all the way up, back down: one rep."])
        case .lunge:
            Placement(
                headline: "Phone to your side, at hip height",
                steps: ["Stand the phone upright 2.5–3 m to your side, about hip height. Your shoulder faces the phone, not your chest.",
                        "Your hips, knees and feet must stay in view at the bottom of each lunge.",
                        "Each leg counts: alternating lunges count one per side."])
        case .romanianDeadlift:
            Placement(
                headline: "Phone at an angle, in front of you",
                steps: ["Stand the phone upright 2.5–3 m away, about hip height, halfway between in front of you and to your side.",
                        "With a barbell, never straight side-on: the plates hide your hips when you stand up. Dumbbells can be side-on.",
                        "Keep your head in view when you stand tall between reps."])
        case .crunch:
            Placement(
                headline: "Phone on the floor, to your side",
                steps: ["Stand the phone upright on the floor 2–2.5 m to your side.",
                        "Lie side-on to it, knees bent. Your head, shoulders and hips must be in view.",
                        "Curl your shoulders off the floor and back down: one rep."])
        }
    }

}

public struct Placement: Sendable {
    public let headline: String
    public let steps: [String]
}

public enum CountPoint: Sendable {
    /// When the peak of the rep is reached (pull-up: chin over the bar).
    case peak
    /// When the body is back at rest after reaching the peak.
    case completion
}

public struct RepThresholds: Sendable {
    /// Progress that counts as reaching full depth.
    public var peak: Double
    /// Progress at or below which the body is back at rest.
    public var rest: Double
    /// Progress that marks a rep as started; one that ends below `peak` is a partial rep.
    public var started: Double = 0.4
    /// Consecutive frames a threshold must hold, so one noisy frame cannot flip the state.
    public var confirmFrames = 2
    /// Reps faster than this are noise, not reps.
    public var minimumRepInterval: TimeInterval = 0.6
    /// A rep that goes from start to count quicker than this is a detection glitch, such as the
    /// knees swapping labels for a few frames mid-lunge, not a rep.
    public var minimumRepDuration: TimeInterval = 0
    /// Joints missing for longer than this abandon a rep in flight.
    public var maximumGap: TimeInterval = 0.6
}
