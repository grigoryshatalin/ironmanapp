import Foundation

/// Rearranges the days *within* a training week so the athlete's preferred long
/// ride, long run, and rest day land on the weekdays they chose during
/// onboarding (§7 "the stored plan must remain adaptable if the user chooses
/// different long-session days").
///
/// Why a whole-day permutation rather than moving individual workouts: the
/// plan's weekly rhythm is deliberate — the brick run follows the long ride, a
/// recovery day follows the long run, hard sessions are spaced. Permuting whole
/// days preserves every one of those relationships and only changes which
/// weekday each lands on. Moving one workout would quietly destroy them.
///
/// Roles are *derived from plan content*, never hard-coded to Saturday/Sunday,
/// so this keeps working for coach-authored plans with a different rhythm
/// (§28.12) and for taper weeks that contain no long ride at all.
public struct WeekdayLayout: Sendable, Equatable {

    /// `destinations[source] = destination`, a permutation of `0..<7`.
    public let destinations: [Int]

    public init(destinations: [Int]) {
        self.destinations = destinations
    }

    /// The no-op layout: every day stays where the plan put it.
    public static let identity = WeekdayLayout(destinations: Array(0..<7))

    public var isIdentity: Bool { destinations == Array(0..<7) }

    /// Where a plan day with `sourceOffset` should actually fall.
    public func destination(for sourceOffset: Int) -> Int {
        guard destinations.indices.contains(sourceOffset) else { return sourceOffset }
        return destinations[sourceOffset]
    }

    /// Build the layout for one week from the athlete's preferences.
    ///
    /// Rest is honoured first: protecting a genuine recovery day matters more
    /// than which weekday carries the long ride. A role is skipped when the week
    /// does not contain it (a taper week may have no long ride) or when its
    /// target weekday was already claimed by a higher-priority role — the plan's
    /// own ordering then fills the remaining slots in relative order, so the
    /// result is always a valid permutation.
    /// - Parameter planStartWeekday: the Gregorian weekday (1 = Sun … 7 = Sat)
    ///   that plan day 0 actually falls on. This is **not** the same as
    ///   `config.startWeekday`, which is the plan's nominal week-start and is
    ///   hardcoded to Monday by onboarding while the athlete picks any start
    ///   date. Deriving offsets from the nominal value silently shifted every
    ///   preferred day by the difference between the two — and did so invisibly,
    ///   because every test used a Monday start.
    public static func make(
        for week: TrainingWeekDefinition,
        config: ScheduleConfiguration,
        planStartWeekday: Int
    ) -> WeekdayLayout {
        var destination = [Int?](repeating: nil, count: 7)
        var usedTargets = Set<Int>()

        func offset(ofWeekday weekday: Int?) -> Int? {
            guard let weekday, (1...7).contains(weekday) else { return nil }
            return ((weekday - planStartWeekday) % 7 + 7) % 7
        }

        let roles: [(source: Int?, target: Int?)] = [
            (week.restDayOffset, offset(ofWeekday: config.preferredRestWeekday)),
            (week.longRideDayOffset, offset(ofWeekday: config.preferredLongBikeWeekday)),
            (week.longRunDayOffset, offset(ofWeekday: config.preferredLongRunWeekday)),
        ]

        for role in roles {
            guard let source = role.source,
                  let target = role.target,
                  destination.indices.contains(source),
                  destination[source] == nil,
                  !usedTargets.contains(target)
            else { continue }
            destination[source] = target
            usedTargets.insert(target)
        }

        var freeTargets = (0..<7).filter { !usedTargets.contains($0) }
        for source in 0..<7 where destination[source] == nil {
            destination[source] = freeTargets.isEmpty ? source : freeTargets.removeFirst()
        }

        return WeekdayLayout(destinations: destination.enumerated().map { $1 ?? $0 })
    }
}

// MARK: - Deriving the roles from plan content

extension TrainingDayDefinition {
    /// Total planned minutes of required (non-optional) work on this day.
    public var requiredPlannedMinutes: Int {
        workouts.filter { !$0.isOptional }.reduce(0) { $0 + $1.plannedDurationMinutes }
    }

    func plannedMinutes(for sport: Sport) -> Int {
        workouts.filter { $0.sport == sport }.reduce(0) { $0 + $1.plannedDurationMinutes }
    }

    func hasLongSession(in sport: Sport) -> Bool {
        workouts.contains { $0.sport == sport && $0.stressCategory == .long }
    }
}

extension TrainingWeekDefinition {

    /// The weekday offset carrying this week's long ride, if it has one.
    public var longRideDayOffset: Int? { longSessionOffset(for: .bike) }

    /// The weekday offset carrying this week's long run, if it has one.
    public var longRunDayOffset: Int? { longSessionOffset(for: .run) }

    /// The week's rest day: a day with no required work, else the lightest day.
    /// Ties resolve to the earliest offset so the result is deterministic.
    public var restDayOffset: Int? {
        let ordered = days.sorted { $0.weekdayOffset < $1.weekdayOffset }
        guard !ordered.isEmpty else { return nil }
        if let rest = ordered.first(where: { $0.isRestDay }) { return rest.weekdayOffset }
        return ordered.min { $0.requiredPlannedMinutes < $1.requiredPlannedMinutes }?.weekdayOffset
    }

    /// Prefer a day explicitly marked as a `.long` session in that sport; fall
    /// back to the day with the most minutes in it. Returns nil when the week
    /// contains no work in that sport at all.
    private func longSessionOffset(for sport: Sport) -> Int? {
        let ordered = days.sorted { $0.weekdayOffset < $1.weekdayOffset }
        let flagged = ordered.filter { $0.hasLongSession(in: sport) }
        let candidates = flagged.isEmpty ? ordered.filter { $0.plannedMinutes(for: sport) > 0 } : flagged
        guard !candidates.isEmpty else { return nil }
        return candidates.max { $0.plannedMinutes(for: sport) < $1.plannedMinutes(for: sport) }?.weekdayOffset
    }
}
