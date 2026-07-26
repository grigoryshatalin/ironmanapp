import Foundation

/// Load designation for a week — drives recovery-week highlighting on the Plan
/// and Progress screens, and the safety rule that missed volume is not restored
/// into a recovery week without explicit action (§14).
public enum WeekLoad: String, Codable, CaseIterable, Sendable, Hashable {
    case base
    case build
    case recovery
    case peak
    case taper
    case race

    public var localizationKey: String { "weekload.\(rawValue)" }

    /// Recovery, taper, and race weeks should not absorb restored missed volume.
    public var acceptsRestoredVolume: Bool {
        switch self {
        case .base, .build, .peak: return true
        case .recovery, .taper, .race: return false
        }
    }
}

/// One day of the plan. `weekdayOffset` is 0–6 within the training week (0 = the
/// plan's start weekday). `dayIndex` is the global 0-based index across the plan
/// and is what `ScheduleEngine` adds to the start date.
public struct TrainingDayDefinition: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var dayIndex: Int
    public var weekdayOffset: Int
    public var title: String
    public var objective: String
    public var workouts: [WorkoutTemplate]
    public var nutrition: DayNutrition?
    public var recovery: RecoveryGuidance?
    public var notes: String?

    public init(
        id: UUID = UUID(),
        dayIndex: Int,
        weekdayOffset: Int,
        title: String,
        objective: String,
        workouts: [WorkoutTemplate] = [],
        nutrition: DayNutrition? = nil,
        recovery: RecoveryGuidance? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.dayIndex = dayIndex
        self.weekdayOffset = weekdayOffset
        self.title = title
        self.objective = objective
        self.workouts = workouts
        self.nutrition = nutrition
        self.recovery = recovery
        self.notes = notes
    }

    /// True when the day has no non-optional workouts (a rest day).
    public var isRestDay: Bool {
        !workouts.contains { !$0.isOptional }
    }
}

/// One week of the plan.
public struct TrainingWeekDefinition: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var weekNumber: Int        // 1-based
    public var phaseID: UUID
    public var title: String
    public var objective: String
    public var load: WeekLoad
    public var plannedMinutes: Int
    public var days: [TrainingDayDefinition]
    public var coachNote: String?

    public init(
        id: UUID = UUID(),
        weekNumber: Int,
        phaseID: UUID,
        title: String,
        objective: String,
        load: WeekLoad,
        plannedMinutes: Int,
        days: [TrainingDayDefinition],
        coachNote: String? = nil
    ) {
        self.id = id
        self.weekNumber = weekNumber
        self.phaseID = phaseID
        self.title = title
        self.objective = objective
        self.load = load
        self.plannedMinutes = plannedMinutes
        self.days = days
        self.coachNote = coachNote
    }
}

/// A macro training phase spanning a range of weeks.
public struct TrainingPhaseDefinition: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    public var startWeek: Int
    public var endWeek: Int
    public var objective: String
    public var defaultLoad: WeekLoad

    public init(
        id: UUID = UUID(),
        name: String,
        startWeek: Int,
        endWeek: Int,
        objective: String,
        defaultLoad: WeekLoad
    ) {
        self.id = id
        self.name = name
        self.startWeek = startWeek
        self.endWeek = endWeek
        self.objective = objective
        self.defaultLoad = defaultLoad
    }
}

/// Descriptive, non-personal metadata about a plan.
public struct PlanMetadata: Codable, Sendable, Hashable {
    public var author: String
    public var version: String
    public var athleteLevel: String
    public var goal: String
    public var createdISO8601: String?
    public var tags: [String]
    public var disclaimer: String

    public init(
        author: String,
        version: String,
        athleteLevel: String,
        goal: String,
        createdISO8601: String? = nil,
        tags: [String] = [],
        disclaimer: String
    ) {
        self.author = author
        self.version = version
        self.athleteLevel = athleteLevel
        self.goal = goal
        self.createdISO8601 = createdISO8601
        self.tags = tags
        self.disclaimer = disclaimer
    }
}

/// The complete immutable training plan (§15 `TrainingPlan`). Carries no
/// absolute calendar dates — `ScheduleEngine` maps day indices onto real dates
/// from the athlete's chosen start/race date.
public struct TrainingPlanDefinition: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var schemaVersion: Int
    public var name: String
    public var summary: String
    public var durationWeeks: Int
    /// Weekday the plan's weeks begin on, as a Gregorian `Calendar` weekday
    /// (1 = Sunday … 7 = Saturday). Default Monday = 2.
    public var startWeekday: Int
    public var phases: [TrainingPhaseDefinition]
    public var weeks: [TrainingWeekDefinition]
    public var metadata: PlanMetadata

    public init(
        id: UUID = UUID(),
        schemaVersion: Int,
        name: String,
        summary: String,
        durationWeeks: Int,
        startWeekday: Int = 2,
        phases: [TrainingPhaseDefinition],
        weeks: [TrainingWeekDefinition],
        metadata: PlanMetadata
    ) {
        self.id = id
        self.schemaVersion = schemaVersion
        self.name = name
        self.summary = summary
        self.durationWeeks = durationWeeks
        self.startWeekday = startWeekday
        self.phases = phases
        self.weeks = weeks
        self.metadata = metadata
    }

    /// Total number of days the plan spans.
    public var totalDays: Int { durationWeeks * 7 }

    /// All days flattened in chronological order.
    public var allDays: [TrainingDayDefinition] {
        weeks
            .sorted { $0.weekNumber < $1.weekNumber }
            .flatMap { $0.days.sorted { $0.weekdayOffset < $1.weekdayOffset } }
    }

    /// The phase that governs a given 1-based week number, if any.
    public func phase(forWeek weekNumber: Int) -> TrainingPhaseDefinition? {
        phases.first { weekNumber >= $0.startWeek && weekNumber <= $0.endWeek }
    }
}
