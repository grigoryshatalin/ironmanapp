import Foundation

/// Live metrics for a session in progress (§G).
///
/// Every field is optional and defaults to absent. That is the point: a metric
/// is shown only when the device genuinely produced it. An iPhone with no paired
/// Watch has no heart rate, and reporting `0 bpm` — or worse, deriving a
/// plausible-looking average from nothing — would be fabricating data the
/// athlete may act on. Absent renders as "—".
public struct ActiveWorkoutMetrics: Codable, Sendable, Hashable {

    /// Wall-time since the session began, including pauses.
    public var elapsedSeconds: TimeInterval
    /// Time actually accruing, excluding pauses. From a monotonic clock.
    public var activeSeconds: TimeInterval

    public var distanceMeters: Double?
    public var heartRateBPM: Int?
    public var averageHeartRateBPM: Int?
    public var activeEnergyKilocalories: Double?
    public var currentPaceSecondsPerKilometre: Double?
    public var averagePaceSecondsPerKilometre: Double?
    public var currentSpeedMetresPerSecond: Double?
    public var averageSpeedMetresPerSecond: Double?
    public var currentPowerWatts: Int?
    public var averagePowerWatts: Int?

    public init(
        elapsedSeconds: TimeInterval = 0,
        activeSeconds: TimeInterval = 0,
        distanceMeters: Double? = nil,
        heartRateBPM: Int? = nil,
        averageHeartRateBPM: Int? = nil,
        activeEnergyKilocalories: Double? = nil,
        currentPaceSecondsPerKilometre: Double? = nil,
        averagePaceSecondsPerKilometre: Double? = nil,
        currentSpeedMetresPerSecond: Double? = nil,
        averageSpeedMetresPerSecond: Double? = nil,
        currentPowerWatts: Int? = nil,
        averagePowerWatts: Int? = nil
    ) {
        self.elapsedSeconds = elapsedSeconds
        self.activeSeconds = activeSeconds
        self.distanceMeters = distanceMeters
        self.heartRateBPM = heartRateBPM
        self.averageHeartRateBPM = averageHeartRateBPM
        self.activeEnergyKilocalories = activeEnergyKilocalories
        self.currentPaceSecondsPerKilometre = currentPaceSecondsPerKilometre
        self.averagePaceSecondsPerKilometre = averagePaceSecondsPerKilometre
        self.currentSpeedMetresPerSecond = currentSpeedMetresPerSecond
        self.averageSpeedMetresPerSecond = averageSpeedMetresPerSecond
        self.currentPowerWatts = currentPowerWatts
        self.averagePowerWatts = averagePowerWatts
    }

    /// Average pace derived from distance and active time.
    ///
    /// Returns nil rather than infinity when nothing has been covered yet — a
    /// pace of "∞ /km" in the first seconds of a run is noise, not information.
    public static func pace(
        distanceMeters: Double?, activeSeconds: TimeInterval
    ) -> Double? {
        guard let distanceMeters, distanceMeters > 0, activeSeconds > 0 else { return nil }
        return activeSeconds / (distanceMeters / 1000)
    }

    public static func speed(
        distanceMeters: Double?, activeSeconds: TimeInterval
    ) -> Double? {
        guard let distanceMeters, distanceMeters > 0, activeSeconds > 0 else { return nil }
        return distanceMeters / activeSeconds
    }

    /// Which metrics are worth showing for a sport, so the UI does not reserve
    /// space for a value the session will never produce.
    public static func relevantFields(for sport: Sport) -> Set<Field> {
        switch sport {
        case .run:   return [.elapsed, .distance, .pace, .heartRate, .energy]
        case .bike:  return [.elapsed, .distance, .speed, .power, .heartRate, .energy]
        case .swim:  return [.elapsed, .distance, .pace, .heartRate]
        case .strength, .mobility, .recovery: return [.elapsed, .heartRate, .energy]
        case .brick, .race: return [.elapsed, .distance, .pace, .heartRate, .energy]
        }
    }

    public enum Field: String, Codable, Sendable, Hashable, CaseIterable {
        case elapsed, distance, pace, speed, power, heartRate, energy
    }
}

// MARK: - Interval position

/// Where the athlete is within a structured session (§G: current interval,
/// remaining time or distance, upcoming interval).
public struct IntervalProgress: Sendable, Hashable {
    public var currentIndex: Int
    public var totalSteps: Int
    public var current: WorkoutStep?
    public var upcoming: WorkoutStep?
    /// Remaining in the current step, when the step states a duration.
    public var remainingSeconds: TimeInterval?
    /// Remaining in the current step, when the step states a distance.
    public var remainingMeters: Double?

    public init(
        currentIndex: Int, totalSteps: Int,
        current: WorkoutStep?, upcoming: WorkoutStep?,
        remainingSeconds: TimeInterval? = nil, remainingMeters: Double? = nil
    ) {
        self.currentIndex = currentIndex
        self.totalSteps = totalSteps
        self.current = current
        self.upcoming = upcoming
        self.remainingSeconds = remainingSeconds
        self.remainingMeters = remainingMeters
    }

    public var isComplete: Bool { currentIndex >= totalSteps }
}

/// Flattens a template into the ordered steps an athlete actually performs, and
/// answers "where am I now".
///
/// Repeats are expanded here rather than tracked as a nested cursor: a step that
/// repeats four times is four steps to the person doing it, and modelling it any
/// other way pushes that arithmetic into the UI where it gets done differently
/// in each place.
public struct IntervalTracker: Sendable {

    public let steps: [WorkoutStep]

    public init(template: WorkoutTemplate?) {
        guard let template else { self.steps = []; return }
        self.steps = Self.flatten(template.warmup)
            + Self.flatten(template.mainSet)
            + Self.flatten(template.cooldown)
    }

    /// Flattens too. An earlier version assigned these through unchanged, so a
    /// tracker built from steps expanded repeats while one built from a template
    /// did not — the same input describing a different workout depending on
    /// which initializer the caller happened to use.
    public init(steps: [WorkoutStep]) { self.steps = Self.flatten(steps) }

    private static func flatten(_ steps: [WorkoutStep]) -> [WorkoutStep] {
        steps.flatMap { step -> [WorkoutStep] in
            let expansion = step.childSteps.isEmpty ? [step] : flatten(step.childSteps)
            return Array(repeating: expansion, count: max(1, step.repeats)).flatMap { $0 }
        }
    }

    public var totalSteps: Int { steps.count }

    public func progress(
        atIndex index: Int,
        elapsedInStep: TimeInterval = 0,
        distanceInStep: Double = 0
    ) -> IntervalProgress {
        let current = steps.indices.contains(index) ? steps[index] : nil
        let upcoming = steps.indices.contains(index + 1) ? steps[index + 1] : nil

        var remainingSeconds: TimeInterval?
        if let duration = current?.durationSeconds, duration > 0 {
            remainingSeconds = max(0, TimeInterval(duration) - elapsedInStep)
        }
        var remainingMeters: Double?
        if let distance = current?.distanceMeters, distance > 0 {
            remainingMeters = max(0, distance - distanceInStep)
        }

        return IntervalProgress(
            currentIndex: index, totalSteps: steps.count,
            current: current, upcoming: upcoming,
            remainingSeconds: remainingSeconds, remainingMeters: remainingMeters)
    }

    /// Whether the current step has been satisfied, so the UI can offer to
    /// advance. Deliberately not automatic: a step with no stated goal is
    /// athlete-judged, and auto-advancing past it would be guessing.
    public func isStepComplete(
        atIndex index: Int, elapsedInStep: TimeInterval, distanceInStep: Double
    ) -> Bool {
        guard let step = steps.indices.contains(index) ? steps[index] : nil else { return false }
        if let duration = step.durationSeconds, duration > 0 {
            return elapsedInStep >= TimeInterval(duration)
        }
        if let distance = step.distanceMeters, distance > 0 {
            return distanceInStep >= distance
        }
        return false
    }
}
