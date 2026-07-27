import Foundation

/// The active-workout state machine (§G).
///
/// The brief forbids scattered `isRunning` / `isPaused` / `isSaving` booleans,
/// and for good reason: those admit impossible combinations (paused *and*
/// saving, running *and* discarded) that only show up as a stuck UI on a wrist
/// halfway through a long ride. This models the lifecycle as one explicit
/// value with explicit legal transitions, so an illegal move is a compile-time
/// or test-time failure rather than a field report.
///
/// Kept Foundation-only: HealthKit drives this, but does not appear in it.
public enum ActiveWorkoutState: String, Codable, Sendable, Hashable, CaseIterable {
    case idle
    case preparing
    case starting
    case running
    case paused
    case resuming
    case ending
    case saving
    case completed
    case discarded
    case failed
    /// Re-establishing state after termination or disconnection.
    case recovering

    public var localizationKey: String { "activeworkout.\(rawValue)" }

    /// States in which workout time is accruing.
    public var isAccruingTime: Bool {
        switch self {
        case .running, .resuming: return true
        case .idle, .preparing, .starting, .paused, .ending,
             .saving, .completed, .discarded, .failed, .recovering: return false
        }
    }

    /// States from which no further transition is possible.
    public var isTerminal: Bool {
        switch self {
        case .completed, .discarded: return true
        default: return false
        }
    }

    /// Whether a session is meaningfully in progress — used to decide whether a
    /// Live Activity should exist (§J) and whether recovery is needed.
    public var isActive: Bool {
        switch self {
        case .preparing, .starting, .running, .paused, .resuming, .ending, .saving, .recovering:
            return true
        case .idle, .completed, .discarded, .failed:
            return false
        }
    }
}

/// The events that can move a workout between states.
public enum ActiveWorkoutEvent: String, Codable, Sendable, Hashable, CaseIterable {
    case prepare
    case start
    case sessionDidStart
    case pause
    case sessionDidPause
    case resume
    case sessionDidResume
    case end
    case sessionDidEnd
    case saveSucceeded
    case saveFailed
    case discard
    case interrupted
    case recovered
    case retry
}

/// A pure, testable transition table.
///
/// Deliberately a value type with no framework dependencies so every transition
/// — including the illegal ones — can be asserted without a watch, a phone, or
/// a HealthKit authorization prompt.
public struct ActiveWorkoutMachine: Sendable, Equatable {

    public private(set) var state: ActiveWorkoutState

    public init(state: ActiveWorkoutState = .idle) {
        self.state = state
    }

    public enum TransitionError: Error, Sendable, Equatable {
        case illegal(from: ActiveWorkoutState, event: ActiveWorkoutEvent)
    }

    /// The state an event would produce, or `nil` when the move is illegal.
    public static func destination(
        from state: ActiveWorkoutState,
        on event: ActiveWorkoutEvent
    ) -> ActiveWorkoutState? {
        switch (state, event) {
        case (.idle, .prepare): return .preparing
        case (.idle, .start): return .starting
        case (.preparing, .start): return .starting
        case (.preparing, .discard): return .discarded

        case (.starting, .sessionDidStart): return .running
        case (.starting, .saveFailed): return .failed
        case (.starting, .interrupted): return .recovering

        case (.running, .pause): return .paused
        case (.running, .sessionDidPause): return .paused
        case (.running, .end): return .ending
        case (.running, .interrupted): return .recovering

        case (.paused, .resume): return .resuming
        case (.paused, .sessionDidResume): return .running
        case (.paused, .end): return .ending
        case (.paused, .interrupted): return .recovering

        case (.resuming, .sessionDidResume): return .running
        case (.resuming, .interrupted): return .recovering

        case (.ending, .sessionDidEnd): return .saving
        case (.ending, .interrupted): return .recovering

        // Discarding is permitted right up to the point of saving, but never
        // after a successful save — that would be data loss, not a discard.
        case (.running, .discard), (.paused, .discard), (.ending, .discard), (.saving, .discard):
            return .discarded

        case (.saving, .saveSucceeded): return .completed
        case (.saving, .saveFailed): return .failed

        // A failed save keeps the data and stays retryable.
        case (.failed, .retry): return .saving
        case (.failed, .discard): return .discarded

        // Recovery returns to a known-good state decided by the caller.
        case (.recovering, .recovered): return .running
        case (.recovering, .end): return .ending
        case (.recovering, .discard): return .discarded
        case (.recovering, .saveFailed): return .failed

        default: return nil
        }
    }

    @discardableResult
    public mutating func apply(_ event: ActiveWorkoutEvent) throws -> ActiveWorkoutState {
        guard let next = Self.destination(from: state, on: event) else {
            throw TransitionError.illegal(from: state, event: event)
        }
        state = next
        return next
    }

    public func canApply(_ event: ActiveWorkoutEvent) -> Bool {
        Self.destination(from: state, on: event) != nil
    }
}

// MARK: - Elapsed time

/// Accumulates workout time from a **monotonic** clock (§G).
///
/// Wall-clock subtraction is wrong here: a time-zone change, an NTP correction,
/// or a manual clock change mid-session would silently corrupt elapsed time on a
/// long ride. `uptimeNanoseconds` only moves forward, so pause/resume arithmetic
/// stays honest.
public struct MonotonicStopwatch: Sendable, Equatable {
    /// Total time accrued before the current running segment.
    private var accumulated: TimeInterval
    /// Monotonic reading when the current segment began; nil when not running.
    private var segmentStart: UInt64?

    public init(accumulated: TimeInterval = 0, segmentStart: UInt64? = nil) {
        self.accumulated = accumulated
        self.segmentStart = segmentStart
    }

    public var isRunning: Bool { segmentStart != nil }

    public mutating func start(now: UInt64) {
        guard segmentStart == nil else { return }
        segmentStart = now
    }

    public mutating func pause(now: UInt64) {
        guard let started = segmentStart else { return }
        accumulated += Self.seconds(from: started, to: now)
        segmentStart = nil
    }

    public func elapsed(now: UInt64) -> TimeInterval {
        guard let started = segmentStart else { return accumulated }
        return accumulated + Self.seconds(from: started, to: now)
    }

    /// Persisted form, so elapsed time survives app termination (§G recovery).
    public var accumulatedSeconds: TimeInterval { accumulated }

    private static func seconds(from start: UInt64, to end: UInt64) -> TimeInterval {
        guard end > start else { return 0 }
        return TimeInterval(end - start) / 1_000_000_000
    }
}

// MARK: - Recovery

/// Enough state to resume a session after the app or watch is terminated (§G).
public struct ActiveWorkoutRecovery: Codable, Sendable, Hashable {
    public var scheduledWorkoutID: UUID?
    public var executionID: UUID
    public var state: ActiveWorkoutState
    public var sport: Sport
    /// Wall-clock start, for display and HealthKit only — never for elapsed time.
    public var startedAt: Date
    public var accumulatedSeconds: TimeInterval
    public var currentStepIndex: Int
    public var updatedAt: Date

    public init(
        scheduledWorkoutID: UUID?,
        executionID: UUID,
        state: ActiveWorkoutState,
        sport: Sport,
        startedAt: Date,
        accumulatedSeconds: TimeInterval,
        currentStepIndex: Int = 0,
        updatedAt: Date = Date()
    ) {
        self.scheduledWorkoutID = scheduledWorkoutID
        self.executionID = executionID
        self.state = state
        self.sport = sport
        self.startedAt = startedAt
        self.accumulatedSeconds = accumulatedSeconds
        self.currentStepIndex = currentStepIndex
        self.updatedAt = updatedAt
    }

    /// A record only needs recovering if its state was still live.
    public var needsRecovery: Bool { state.isActive }
}
