import Foundation

/// One thing to say.
public struct Utterance: Sendable, Equatable {
    public let text: String
    /// Synthesized ahead of time and played from memory, so it starts the instant it is needed.
    /// Everything spoken mid-set is; set and session summaries are synthesized live.
    public let precomputed: Bool

    public init(_ text: String, precomputed: Bool) {
        self.text = text
        self.precomputed = precomputed
    }
}

/// Every fixed phrase the app speaks. The precompute pass and the runtime both take their text
/// from here, so a phrase can never be spoken live because its cached copy is worded differently.
public enum PhraseBook {
    /// Counts up to this are precomputed; higher counts are synthesized live.
    public static let maxPrecomputedCount = 60

    public static func count(_ n: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .spellOut
        formatter.locale = Locale(identifier: "en_US")
        let words = formatter.string(from: NSNumber(value: n)) ?? String(n)
        return words.prefix(1).uppercased() + words.dropFirst() + "!"
    }

    public static let ready = "Ready when you are."
    public static let twoMore = "Two more!"
    public static let lastOne = "Last one. You've got this!"
    public static let targetHit = "That's the target! Got one more in you?"
    /// Rotated through for every rep past the target.
    public static let pastTarget = ["One more!", "Keep going!", "You can do another one!", "Strong! One more!"]

    /// The end of the countdown that starts a workout once you are in position, after
    /// "Three!", "Two!", "One!".
    public static let go = "Go!"

    /// Every fixed phrase once, in a fixed order.
    public static var precomputed: [String] {
        var seen: Set<String> = []
        return ((1...maxPrecomputedCount).map(count) + [ready, twoMore, lastOne, targetHit, go] + pastTarget
                + Cue.all.map(\.text) + FormFault.allPhrases).filter { seen.insert($0).inserted }
    }
}

/// Decides what to say. The count always comes first; encouragement follows it near the target.
public struct Coach: Sendable {
    public var target: Int
    public var motivation: Bool
    private var pastTargetIndex = 0

    public init(target: Int, motivation: Bool) {
        self.target = target
        self.motivation = motivation
    }

    public mutating func rep(_ n: Int) -> [Utterance] {
        var lines = [Utterance(PhraseBook.count(n), precomputed: n <= PhraseBook.maxPrecomputedCount)]
        guard motivation, target > 0 else { return lines }
        if n == target - 2, target >= 4 {
            lines.append(Utterance(PhraseBook.twoMore, precomputed: true))
        } else if n == target - 1, target >= 2 {
            lines.append(Utterance(PhraseBook.lastOne, precomputed: true))
        } else if n == target {
            lines.append(Utterance(PhraseBook.targetHit, precomputed: true))
        } else if n > target {
            lines.append(Utterance(PhraseBook.pastTarget[pastTargetIndex % PhraseBook.pastTarget.count], precomputed: true))
            pastTargetIndex += 1
        }
        return lines
    }

    public mutating func setEnded(_ end: SetEnd) -> Utterance? {
        pastTargetIndex = 0
        guard !end.discarded else { return nil }
        var text = "Set \(end.setNumber) done. \(end.reps) reps."
        if motivation, target > 0, end.reps >= target, end.form.isEmpty { text += " Great set!" }
        // Form advice follows; without any, a word to rest.
        return Utterance(end.form.isEmpty && end.reps < 3 ? text + " Rest up." : text, precomputed: false)
    }

    /// What to say about form after a set: up to three short sentences of advice, or one of
    /// praise for a clean set of three or more reps.
    public static func formFeedback(_ faults: [FormFault], reps: Int, exercise: Exercise) -> [Utterance] {
        if faults.isEmpty {
            return reps >= 3 ? [Utterance(FormCheck.praise(exercise), precomputed: true)] : []
        }
        return faults.prefix(3).map { Utterance($0.advice(for: exercise), precomputed: true) }
    }

    public func summary(_ s: WorkoutSummary) -> Utterance {
        guard !s.sets.isEmpty else {
            return Utterance("Workout done. No full sets counted this time.", precomputed: false)
        }
        let setWord = s.sets.count == 1 ? "set" : "sets"
        let list: String
        if s.sets.count == 1 {
            list = "\(s.sets[0])"
        } else {
            list = s.sets.dropLast().map(String.init).joined(separator: ", ") + " and \(s.sets.last!)"
        }
        return Utterance(
            "Workout done. \(s.sets.count) \(setWord) of \(s.exercise.plural): \(list). \(s.totalReps) reps in total. Nice work!",
            precomputed: false)
    }
}
