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
    public var plannedMinutes: Int
    public var completedMinutes: Int
    public var sessionCount: Int
    public var completedSessionCount: Int
    public var isRecoveryDay: Bool

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
        sessionCount: Int,
        completedSessionCount: Int,
        isRecoveryDay: Bool
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
        self.sessionCount = sessionCount
        self.completedSessionCount = completedSessionCount
        self.isRecoveryDay = isRecoveryDay
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
