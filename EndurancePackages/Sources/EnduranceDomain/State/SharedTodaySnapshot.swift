import Foundation

/// A compact, cheap-to-decode snapshot of "today" for extensions — widgets, App
/// Intents, the watch face (§28.19). Extensions read THIS from the App Group
/// container rather than opening the full SwiftData store, so they stay fast and
/// don't need the whole persistence stack.
public struct SharedTodaySnapshot: Codable, Sendable, Hashable {
    public var generatedAt: Date
    public var trainingDayID: UUID?
    public var weekNumber: Int
    public var totalWeeks: Int
    public var phaseName: String
    public var nextWorkoutID: UUID?
    public var nextWorkoutTitle: String?
    public var nextWorkoutSport: Sport?
    public var nextWorkoutStart: Date?
    /// **Today's** minutes. These were populated from the *week's* progress
    /// while being named and displayed as today's, so the widget and the "how's
    /// today going" intent both quoted a weekly figure as a daily one.
    public var plannedMinutes: Int
    public var completedMinutes: Int
    /// The week's minutes, kept separately rather than inferred.
    public var weekPlannedMinutes: Int
    public var weekCompletedMinutes: Int
    public var sessionCount: Int
    public var completedSessionCount: Int
    public var isRecoveryDay: Bool
    /// One entry per day of the current training week, so a medium widget can
    /// show the week rather than a larger copy of the day. Deliberately tiny —
    /// seven small structs, not seven workouts — because this file is read on
    /// every timeline refresh.
    public var week: [DaySummary]

    public struct DaySummary: Codable, Sendable, Hashable, Identifiable {
        public var id: Int { weekdayOffset }
        /// 0-based offset within the training week.
        public var weekdayOffset: Int
        /// One or two letters, already localized by the writer.
        public var initial: String
        public var plannedMinutes: Int
        public var completedMinutes: Int
        public var isToday: Bool
        public var isRest: Bool

        public init(
            weekdayOffset: Int, initial: String, plannedMinutes: Int,
            completedMinutes: Int, isToday: Bool, isRest: Bool
        ) {
            self.weekdayOffset = weekdayOffset
            self.initial = initial
            self.plannedMinutes = plannedMinutes
            self.completedMinutes = completedMinutes
            self.isToday = isToday
            self.isRest = isRest
        }

        public var fraction: Double {
            guard plannedMinutes > 0 else { return 0 }
            return min(1, Double(completedMinutes) / Double(plannedMinutes))
        }
    }

    public init(
        generatedAt: Date,
        trainingDayID: UUID? = nil,
        weekNumber: Int,
        totalWeeks: Int,
        phaseName: String,
        nextWorkoutID: UUID? = nil,
        nextWorkoutTitle: String? = nil,
        nextWorkoutSport: Sport? = nil,
        nextWorkoutStart: Date? = nil,
        plannedMinutes: Int,
        completedMinutes: Int,
        weekPlannedMinutes: Int = 0,
        weekCompletedMinutes: Int = 0,
        sessionCount: Int,
        completedSessionCount: Int,
        isRecoveryDay: Bool,
        week: [DaySummary] = []
    ) {
        self.generatedAt = generatedAt
        self.trainingDayID = trainingDayID
        self.weekNumber = weekNumber
        self.totalWeeks = totalWeeks
        self.phaseName = phaseName
        self.nextWorkoutID = nextWorkoutID
        self.nextWorkoutTitle = nextWorkoutTitle
        self.nextWorkoutSport = nextWorkoutSport
        self.nextWorkoutStart = nextWorkoutStart
        self.plannedMinutes = plannedMinutes
        self.completedMinutes = completedMinutes
        self.weekPlannedMinutes = weekPlannedMinutes
        self.weekCompletedMinutes = weekCompletedMinutes
        self.sessionCount = sessionCount
        self.completedSessionCount = completedSessionCount
        self.isRecoveryDay = isRecoveryDay
        self.week = week
    }

    /// Placeholder used by widget previews before real data is available.
    public static let placeholder = SharedTodaySnapshot(
        generatedAt: Date(timeIntervalSinceReferenceDate: 0),
        weekNumber: 4,
        totalWeeks: 36,
        phaseName: "Base",
        nextWorkoutTitle: "Endurance ride",
        nextWorkoutSport: .bike,
        plannedMinutes: 150,
        completedMinutes: 45,
        sessionCount: 2,
        completedSessionCount: 1,
        isRecoveryDay: false
    )
}
