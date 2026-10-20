import Foundation

public enum RepEvent: Sendable, Equatable {
    /// A full rep. `duration` is from leaving rest to the moment it was counted.
    case rep(duration: TimeInterval)
    /// A rep started but turned back before full depth; it does not count.
    case partial(depth: Double)
}

/// Counts reps from a 0…1 progress signal with hysteresis: a rep has to leave rest, reach
/// `peak`, and (for completion-counted exercises) come back to `rest` before it counts. The gap
/// between the thresholds stops jitter at either end from counting twice, and both thresholds
/// must hold for a couple of frames.
///
/// The hysteresis idea comes from RepCounterSDK's `ThresholdCounter` (MIT, see
/// THIRD_PARTY_NOTICES.md); the phases, frame confirmation and gap handling are new.
///
/// The counter starts out needing to see the rest position, so starting the session at the
/// bottom of a squat, or already hanging at the top of a pull-up, does not produce a rep.
public struct RepCounter: Sendable {
    public enum Phase: Sendable, Equatable {
        /// Waiting to see the rest position before anything can count.
        case needsRest
        case atRest
        /// Moving into a rep; `deepest` is the most progress seen so far.
        case descending(start: TimeInterval, deepest: Double)
        /// Reached the peak; `counted` says whether this rep was already counted there.
        case peaked(start: TimeInterval, counted: Bool)
    }

    public let thresholds: RepThresholds
    public let countsAt: CountPoint
    public private(set) var phase: Phase = .needsRest
    public private(set) var lastProgress: Double?

    private var lastSeen: TimeInterval?
    private var lastRepTime: TimeInterval = -.infinity
    private var peakFrames = 0
    private var restFrames = 0

    public init(exercise: Exercise) {
        self.init(thresholds: exercise.thresholds, countsAt: exercise.countsAt)
    }

    public init(thresholds: RepThresholds, countsAt: CountPoint) {
        self.thresholds = thresholds
        self.countsAt = countsAt
    }

    /// Whether the body is at rest, which is when the signal may re-calibrate.
    public var isAtRest: Bool {
        switch phase {
        case .needsRest, .atRest: true
        default: false
        }
    }

    public mutating func reset() {
        self = RepCounter(thresholds: thresholds, countsAt: countsAt)
    }

    public mutating func update(_ reading: SignalReading, at time: TimeInterval) -> RepEvent? {
        let progress: Double
        switch reading {
        case .disengaged:
            phase = .needsRest
            lastProgress = nil
            return nil
        case .unseen:
            if let seen = lastSeen, time - seen > thresholds.maximumGap, !isAtRest {
                phase = .needsRest
            }
            lastProgress = nil
            return nil
        case let .progress(p):
            progress = p
            lastSeen = time
            lastProgress = p
        }

        peakFrames = progress >= thresholds.peak ? peakFrames + 1 : 0
        restFrames = progress <= thresholds.rest ? restFrames + 1 : 0
        let atPeak = peakFrames >= thresholds.confirmFrames
        let atRest = restFrames >= thresholds.confirmFrames

        switch phase {
        case .needsRest:
            if atRest { phase = .atRest }
            return nil

        case .atRest:
            if progress >= thresholds.started {
                phase = .descending(start: time, deepest: progress)
            }
            return nil

        case let .descending(start, deepest):
            if atPeak {
                if countsAt == .peak {
                    phase = .peaked(start: start, counted: true)
                    return count(at: time, start: start)
                }
                phase = .peaked(start: start, counted: false)
                return nil
            }
            if atRest {
                phase = .atRest
                return .partial(depth: deepest)
            }
            phase = .descending(start: start, deepest: max(deepest, progress))
            return nil

        case let .peaked(start, counted):
            guard atRest else { return nil }
            phase = .atRest
            return counted ? nil : count(at: time, start: start)
        }
    }

    private mutating func count(at time: TimeInterval, start: TimeInterval) -> RepEvent? {
        guard time - lastRepTime >= thresholds.minimumRepInterval,
              time - start >= thresholds.minimumRepDuration
        else { return nil }
        lastRepTime = time
        return .rep(duration: time - start)
    }
}
