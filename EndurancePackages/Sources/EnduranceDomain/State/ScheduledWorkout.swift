import Foundation

/// A plan template bound to a real calendar date, plus all mutable athlete
/// state. This is the unit the Today/Plan screens, notifications, progress, and
/// sync all operate on.
///
/// Planned essentials (`sport`, `plannedDurationMinutes`, `stressCategory`, …)
/// are denormalized from the template at generation time. This lets progress
/// aggregation, notification planning, and conflict rules run against the
/// schedule alone — no need to re-join the full plan, which also keeps widget
/// snapshots and the watch app cheap.
public struct ScheduledWorkout: Codable, Sendable, Hashable, Identifiable {
    // Identity
    public var id: UUID { identity.scheduledWorkoutID }
    public var identity: WorkoutIdentity

    // Position within the plan
    public var weekNumber: Int
    public var weekdayOffset: Int
    public var dayIndex: Int
    public var order: Int

    // Denormalized planned content (from the template)
    public var sport: Sport
    public var title: String
    public var objective: String
    public var plannedDurationMinutes: Int
    public var plannedDistanceMeters: Double?
    public var intensity: IntensityZone
    public var stressCategory: StressCategory
    public var isBrick: Bool
    public var brickGroupID: UUID?
    public var isOptional: Bool

    // Scheduling
    /// The date this workout was first computed for. Never changes — the anchor
    /// for "was this moved?" and for keeping completed sessions attached to
    /// their historical slot (§17).
    public var originalDate: Date
    /// The current planned calendar day (start-of-day, local).
    public var scheduledDate: Date
    /// The current planned start instant (scheduledDate + local time-of-day).
    public var plannedStart: Date

    // Mutable athlete state
    public var status: WorkoutStatus
    public var completion: WorkoutCompletion?
    public var modifications: [PlanModification]
    /// Identifiers of the notification requests currently scheduled for this
    /// workout, so they can be cancelled precisely on completion/reschedule.
    public var notificationIDs: [String]
    /// Set when the athlete shortens the session ("reduce session").
    public var reducedDurationMinutes: Int?

    public init(
        identity: WorkoutIdentity,
        weekNumber: Int,
        weekdayOffset: Int,
        dayIndex: Int,
        order: Int,
        sport: Sport,
        title: String,
        objective: String,
        plannedDurationMinutes: Int,
        plannedDistanceMeters: Double? = nil,
        intensity: IntensityZone,
        stressCategory: StressCategory,
        isBrick: Bool = false,
        brickGroupID: UUID? = nil,
        isOptional: Bool = false,
        originalDate: Date,
        scheduledDate: Date,
        plannedStart: Date,
        status: WorkoutStatus = .planned,
        completion: WorkoutCompletion? = nil,
        modifications: [PlanModification] = [],
        notificationIDs: [String] = [],
        reducedDurationMinutes: Int? = nil
    ) {
        self.identity = identity
        self.weekNumber = weekNumber
        self.weekdayOffset = weekdayOffset
        self.dayIndex = dayIndex
        self.order = order
        self.sport = sport
        self.title = title
        self.objective = objective
        self.plannedDurationMinutes = plannedDurationMinutes
        self.plannedDistanceMeters = plannedDistanceMeters
        self.intensity = intensity
        self.stressCategory = stressCategory
        self.isBrick = isBrick
        self.brickGroupID = brickGroupID
        self.isOptional = isOptional
        self.originalDate = originalDate
        self.scheduledDate = scheduledDate
        self.plannedStart = plannedStart
        self.status = status
        self.completion = completion
        self.modifications = modifications
        self.notificationIDs = notificationIDs
        self.reducedDurationMinutes = reducedDurationMinutes
    }

    /// The duration that actually counts toward "planned" load right now — the
    /// reduced duration if the athlete shortened the session, else the plan's.
    public var effectivePlannedMinutes: Int {
        reducedDurationMinutes ?? plannedDurationMinutes
    }

    /// True when the workout was moved from its original calendar day.
    public var wasMoved: Bool {
        !Calendar(identifier: .gregorian).isDate(scheduledDate, inSameDayAs: originalDate)
    }
}
