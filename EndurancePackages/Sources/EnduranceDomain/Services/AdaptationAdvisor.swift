import Foundation

/// Deterministic, explainable safety rules for missed/moved workouts (§14). The
/// advisor never mutates anything and never auto-moves a session — it returns
/// advisory warnings and the options an athlete may choose. Consistency over
/// preserving one workout; never prescribe training through pain/illness.
public struct AdaptationAdvisor: Sendable {
    public init() {}

    /// Options offered when a workout is missed. Deliberately conservative — no
    /// automatic stacking.
    public enum MissedOption: String, Sendable, CaseIterable, Hashable {
        case skip
        case move
        case shorten
        case replaceWithRecovery
    }

    public struct Warning: Sendable, Hashable, Identifiable {
        public enum Kind: String, Sendable, Hashable {
            case consecutiveHighStress
            case longRunAfterHardRun
            case intervalsBeforeLongRide
            case restoringIntoRecoveryWeek
            case illnessOrPain
        }
        public var id: String { kind.rawValue + ":" + detail }
        public var kind: Kind
        public var message: String
        /// What will remain unchanged if the athlete proceeds (transparency).
        public var whatStaysUnchanged: String
        public var detail: String
    }

    public func missedOptions(for workout: ScheduledWorkout) -> [MissedOption] {
        // Long/race-specific sessions favor shorten/replace over stacking.
        MissedOption.allCases
    }

    /// Evaluate moving `workout` to `newDate`. `loadForDate` lets the caller
    /// supply the target week's load (recovery/taper/race) without coupling the
    /// advisor to plan lookup.
    public func warningsForMoving(
        _ workout: ScheduledWorkout,
        to newDate: Date,
        within schedule: [ScheduledWorkout],
        calendar: Calendar,
        loadForDate: (Date) -> WeekLoad?
    ) -> [Warning] {
        var warnings: [Warning] = []
        let newDay = calendar.startOfDay(for: newDate)

        func sessions(on offset: Int) -> [ScheduledWorkout] {
            guard let d = calendar.date(byAdding: .day, value: offset, to: newDay) else { return [] }
            return schedule.filter { $0.id != workout.id && calendar.isDate($0.scheduledDate, inSameDayAs: d) }
        }

        let dayBefore = sessions(on: -1)
        let sameDay = sessions(on: 0)
        let dayAfter = sessions(on: 1)
        let neighbors = dayBefore + sameDay + dayAfter

        // Rule: avoid consecutive high-stress days.
        if workout.stressCategory.isHighStress,
           (dayBefore + dayAfter).contains(where: { $0.stressCategory.isHighStress }) {
            warnings.append(.init(
                kind: .consecutiveHighStress,
                message: "This puts two demanding sessions on back-to-back days. Consider an easier gap between them.",
                whatStaysUnchanged: "Nothing is moved automatically — this is only a heads-up.",
                detail: workout.id.uuidString))
        }

        // Rule: avoid a long run directly after another demanding run.
        if workout.sport == .run, workout.stressCategory == .long,
           dayBefore.contains(where: { $0.sport == .run && $0.stressCategory.isHighStress }) {
            warnings.append(.init(
                kind: .longRunAfterHardRun,
                message: "A long run the day after a hard run raises injury and fatigue risk.",
                whatStaysUnchanged: "Your other sessions stay where they are.",
                detail: workout.id.uuidString))
        }

        // Rule: avoid maximal bike intervals immediately before the longest ride.
        if workout.sport == .bike, (workout.intensity == .vo2 || workout.intensity == .threshold),
           dayAfter.contains(where: { $0.sport == .bike && $0.stressCategory == .long }) {
            warnings.append(.init(
                kind: .intervalsBeforeLongRide,
                message: "Hard bike intervals right before your longest ride can compromise the key session.",
                whatStaysUnchanged: "The long ride keeps its planned date.",
                detail: workout.id.uuidString))
        }

        // Rule: don't restore missed volume into a recovery/taper/race week.
        if let load = loadForDate(newDate), !load.acceptsRestoredVolume, workout.stressCategory.relativeLoad >= StressCategory.moderate.relativeLoad {
            warnings.append(.init(
                kind: .restoringIntoRecoveryWeek,
                message: "That week is a \(load.rawValue) week — adding this session works against its purpose. Skipping is usually the better choice.",
                whatStaysUnchanged: "The recovery week's lighter load is preserved unless you override this.",
                detail: workout.id.uuidString))
        }

        _ = neighbors // reserved for future density heuristics
        return warnings
    }

    /// A conservative, non-diagnostic prompt when the athlete reports illness or
    /// pain (§14). Never diagnoses; encourages rest and professional advice.
    public func illnessOrPainGuidance() -> Warning {
        Warning(
            kind: .illnessOrPain,
            message: "When you're unwell or in pain, rest is training too. Don't train through it — consider seeing a qualified professional.",
            whatStaysUnchanged: "Your plan and history are untouched; nothing is marked missed for taking care of yourself.",
            detail: "illness")
    }
}
