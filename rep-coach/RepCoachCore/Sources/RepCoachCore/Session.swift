import Foundation

public struct SetEnd: Sendable, Equatable {
    public let setNumber: Int
    public let reps: Int
    /// A single stray rep between sets (bending to pick up a plate) is dropped, not kept as a set.
    public let discarded: Bool
    /// Up to three form faults from the set, most important first. Empty: nothing to fix.
    public var form: [FormFault] = []

    public init(setNumber: Int, reps: Int, discarded: Bool) {
        self.setNumber = setNumber
        self.reps = reps
        self.discarded = discarded
    }
}

public struct WorkoutSummary: Sendable, Equatable {
    public let exercise: Exercise
    public let sets: [Int]
    public let duration: TimeInterval

    public init(exercise: Exercise, sets: [Int], duration: TimeInterval) {
        self.exercise = exercise
        self.sets = sets
        self.duration = duration
    }

    public var totalReps: Int { sets.reduce(0, +) }
}

/// Groups reps into sets: a set opens with its first rep and closes after `restTimeout` seconds
/// without one.
public struct SessionTracker: Sendable {
    public let exercise: Exercise
    public var restTimeout: TimeInterval
    /// Sets with fewer reps than this are discarded when they close.
    public var minimumSetReps = 2

    public private(set) var completedSets: [Int] = []
    public private(set) var repsInSet = 0
    private var lastRepTime: TimeInterval?
    private let startTime: TimeInterval

    public init(exercise: Exercise, restTimeout: TimeInterval, startTime: TimeInterval) {
        self.exercise = exercise
        self.restTimeout = restTimeout
        self.startTime = startTime
    }

    /// The set the next rep belongs to, 1-based.
    public var setNumber: Int { completedSets.count + 1 }
    public var isInSet: Bool { repsInSet > 0 }

    /// Records a rep and returns its number within the set.
    public mutating func rep(at time: TimeInterval) -> Int {
        repsInSet += 1
        lastRepTime = time
        return repsInSet
    }

    /// Movement that is not a counted rep (a half rep, or being mid-rep) keeps the set open.
    public mutating func activity(at time: TimeInterval) {
        if isInSet { lastRepTime = time }
    }

    /// Seconds until the open set closes, or nil when no set is open.
    public func restRemaining(at time: TimeInterval) -> TimeInterval? {
        guard isInSet, let last = lastRepTime else { return nil }
        return max(0, restTimeout - (time - last))
    }

    /// Closes the open set if it has rested long enough.
    public mutating func tick(at time: TimeInterval) -> SetEnd? {
        guard let remaining = restRemaining(at: time), remaining <= 0 else { return nil }
        return closeSet()
    }

    public mutating func finish(at time: TimeInterval) -> WorkoutSummary {
        if isInSet { _ = closeSet() }
        return WorkoutSummary(exercise: exercise, sets: completedSets, duration: time - startTime)
    }

    private mutating func closeSet() -> SetEnd {
        let reps = repsInSet
        repsInSet = 0
        lastRepTime = nil
        guard reps >= minimumSetReps else {
            return SetEnd(setNumber: setNumber, reps: reps, discarded: true)
        }
        completedSets.append(reps)
        return SetEnd(setNumber: completedSets.count, reps: reps, discarded: false)
    }
}
