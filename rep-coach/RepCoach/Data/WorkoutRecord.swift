import Foundation
import RepCoachCore
import SwiftData

/// One finished exercise session, kept on the phone.
@Model
final class WorkoutRecord {
    var date: Date
    var exerciseRaw: String
    var target: Int
    var duration: TimeInterval
    var sets: [Int]

    init(date: Date, exercise: Exercise, target: Int, duration: TimeInterval, sets: [Int]) {
        self.date = date
        self.exerciseRaw = exercise.rawValue
        self.target = target
        self.duration = duration
        self.sets = sets
    }

    var exercise: Exercise { Exercise(rawValue: exerciseRaw) ?? .squat }
    var totalReps: Int { sets.reduce(0, +) }
}

/// User preferences, in UserDefaults.
enum Settings {
    static let restTimeoutKey = "restTimeout"
    static let motivationKey = "motivation"
    static let voiceKey = "voice"
    static let recordPosesKey = "recordPoses"
    static let autoStartKey = "autoStart"

    static func targetKey(_ exercise: Exercise) -> String { "target.\(exercise.rawValue)" }

    static func target(for exercise: Exercise) -> Int {
        let saved = UserDefaults.standard.integer(forKey: targetKey(exercise))
        return saved > 0 ? saved : exercise.defaultTarget
    }
}
