import Foundation

/// Aggregates completion state into the summaries the Progress screen shows.
/// Pure over a `[ScheduledWorkout]` slice so it's trivially testable and reused
/// by widgets and the watch app. Deliberately never implies "more volume =
/// better" — it reports planned vs completed and flags recovery weeks (§11).
public struct ProgressCalculator: Sendable {
    public init() {}

    public struct SportProgress: Sendable, Hashable {
        public var sport: Sport
        public var plannedMinutes: Int
        public var completedMinutes: Int
        public var plannedDistanceMeters: Double
        public var completedDistanceMeters: Double
        public var sessionCount: Int
        public var completedSessionCount: Int
    }

    public struct WeekProgress: Sendable, Hashable {
        public var weekNumber: Int
        public var plannedMinutes: Int
        public var completedMinutes: Int
        public var sessionCount: Int
        public var completedSessionCount: Int
        public var bySport: [SportProgress]

        /// Completed ÷ planned, clamped to [0, 1] and safe when planned == 0.
        public var completionFraction: Double {
            guard plannedMinutes > 0 else { return 0 }
            return min(1.0, Double(completedMinutes) / Double(plannedMinutes))
        }
    }

    // MARK: - Per-workout contributions

    /// Minutes a workout contributes to "planned" load. Optional sessions don't
    /// inflate the target.
    private func plannedMinutes(_ w: ScheduledWorkout) -> Int {
        w.isOptional ? 0 : w.effectivePlannedMinutes
    }

    /// Minutes a workout contributes to "completed" load. Uses logged actuals
    /// when present, else the (possibly reduced) planned duration.
    private func completedMinutes(_ w: ScheduledWorkout) -> Int {
        guard w.status.countsAsDone else { return 0 }
        return w.completion?.actualDurationMinutes ?? w.effectivePlannedMinutes
    }

    private func plannedDistance(_ w: ScheduledWorkout) -> Double {
        w.isOptional ? 0 : (w.plannedDistanceMeters ?? 0)
    }

    private func completedDistance(_ w: ScheduledWorkout) -> Double {
        guard w.status.countsAsDone else { return 0 }
        return w.completion?.actualDistanceMeters ?? w.plannedDistanceMeters ?? 0
    }

    // MARK: - Aggregations

    public func weekProgress(_ weekNumber: Int, in workouts: [ScheduledWorkout]) -> WeekProgress {
        let inWeek = workouts.filter { $0.weekNumber == weekNumber }
        return summarize(weekNumber: weekNumber, inWeek)
    }

    private func summarize(weekNumber: Int, _ inWeek: [ScheduledWorkout]) -> WeekProgress {
        var bySport: [Sport: SportProgress] = [:]
        var plannedTotal = 0, completedTotal = 0, sessions = 0, completedSessions = 0

        for w in inWeek {
            let pm = plannedMinutes(w), cm = completedMinutes(w)
            let pd = plannedDistance(w), cd = completedDistance(w)
            plannedTotal += pm
            completedTotal += cm
            if !w.isOptional { sessions += 1 }
            if w.status.countsAsDone { completedSessions += 1 }

            var sp = bySport[w.sport] ?? SportProgress(
                sport: w.sport, plannedMinutes: 0, completedMinutes: 0,
                plannedDistanceMeters: 0, completedDistanceMeters: 0,
                sessionCount: 0, completedSessionCount: 0
            )
            sp.plannedMinutes += pm
            sp.completedMinutes += cm
            sp.plannedDistanceMeters += pd
            sp.completedDistanceMeters += cd
            if !w.isOptional { sp.sessionCount += 1 }
            if w.status.countsAsDone { sp.completedSessionCount += 1 }
            bySport[w.sport] = sp
        }

        return WeekProgress(
            weekNumber: weekNumber,
            plannedMinutes: plannedTotal,
            completedMinutes: completedTotal,
            sessionCount: sessions,
            completedSessionCount: completedSessions,
            bySport: bySport.values.sorted { $0.sport.rawValue < $1.sport.rawValue }
        )
    }

    /// Planned/completed duration for every week present, ordered by week.
    public func weeklyDurationTrend(in workouts: [ScheduledWorkout]) -> [WeekProgress] {
        let weeks = Set(workouts.map(\.weekNumber)).sorted()
        return weeks.map { weekProgress($0, in: workouts) }
    }

    /// Completion fraction across a set of weeks, by total minutes.
    public func completionFraction(weeks: ClosedRange<Int>, in workouts: [ScheduledWorkout]) -> Double {
        let slice = workouts.filter { weeks.contains($0.weekNumber) }
        let planned = slice.reduce(0) { $0 + plannedMinutes($1) }
        let completed = slice.reduce(0) { $0 + completedMinutes($1) }
        guard planned > 0 else { return 0 }
        return min(1.0, Double(completed) / Double(planned))
    }

    /// Longest *completed* session for a sport, by duration (minutes).
    public func longestCompletedMinutes(sport: Sport, in workouts: [ScheduledWorkout]) -> Int? {
        workouts
            .filter { $0.sport == sport && $0.status.countsAsDone }
            .map { completedMinutes($0) }
            .max()
    }

    /// Consistency over the last `n` weeks ending at `endWeek`: the mean of each
    /// week's completion fraction. Reported as information, not a streak.
    public func consistency(lastWeeks n: Int, endingAt endWeek: Int, in workouts: [ScheduledWorkout]) -> Double {
        guard n > 0 else { return 0 }
        let start = max(1, endWeek - n + 1)
        let weeks = (start...endWeek)
        let fractions = weeks.map { weekProgress($0, in: workouts).completionFraction }
        guard !fractions.isEmpty else { return 0 }
        return fractions.reduce(0, +) / Double(fractions.count)
    }
}
