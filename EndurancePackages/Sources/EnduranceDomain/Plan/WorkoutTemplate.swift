import Foundation

/// Immutable plan content for a single session. This is a *template*: it carries
/// no dates and no completion state. `ScheduleEngine` binds a template to a
/// calendar date to produce a `ScheduledWorkout`, and user state (completion,
/// modifications) lives entirely on that scheduled instance (§15 "Separate
/// immutable plan content from mutable user state").
public struct WorkoutTemplate: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var sport: Sport
    public var title: String
    public var objective: String
    public var plannedDurationMinutes: Int
    public var plannedDistanceMeters: Double?
    public var intensity: IntensityZone
    public var stressCategory: StressCategory

    /// Chronological order within its day (0-based). Two morning + evening
    /// sessions are ordered by this, then by preferred time.
    public var order: Int
    /// Optional fixed local start time. When nil, the app resolves the start
    /// from settings (weekday vs weekend default time).
    public var preferredHour: Int?
    public var preferredMinute: Int?

    // Structured content (§9). Empty arrays are valid (e.g. a mobility session).
    public var warmup: [WorkoutStep]
    public var mainSet: [WorkoutStep]
    public var cooldown: [WorkoutStep]

    public var techniqueCues: [String]
    public var fueling: FuelingGuidance?
    public var hydration: HydrationGuidance?
    public var gear: [String]
    public var safetyNotes: [String]

    public var isBrick: Bool
    /// Groups the bike + run halves of a brick so the UI can present them as a
    /// unit and the schedule keeps them together.
    public var brickGroupID: UUID?
    /// Optional sessions can be dropped without counting as "missed".
    public var isOptional: Bool

    public init(
        id: UUID = UUID(),
        sport: Sport,
        title: String,
        objective: String,
        plannedDurationMinutes: Int,
        plannedDistanceMeters: Double? = nil,
        intensity: IntensityZone,
        stressCategory: StressCategory,
        order: Int = 0,
        preferredHour: Int? = nil,
        preferredMinute: Int? = nil,
        warmup: [WorkoutStep] = [],
        mainSet: [WorkoutStep] = [],
        cooldown: [WorkoutStep] = [],
        techniqueCues: [String] = [],
        fueling: FuelingGuidance? = nil,
        hydration: HydrationGuidance? = nil,
        gear: [String] = [],
        safetyNotes: [String] = [],
        isBrick: Bool = false,
        brickGroupID: UUID? = nil,
        isOptional: Bool = false
    ) {
        self.id = id
        self.sport = sport
        self.title = title
        self.objective = objective
        self.plannedDurationMinutes = plannedDurationMinutes
        self.plannedDistanceMeters = plannedDistanceMeters
        self.intensity = intensity
        self.stressCategory = stressCategory
        self.order = order
        self.preferredHour = preferredHour
        self.preferredMinute = preferredMinute
        self.warmup = warmup
        self.mainSet = mainSet
        self.cooldown = cooldown
        self.techniqueCues = techniqueCues
        self.fueling = fueling
        self.hydration = hydration
        self.gear = gear
        self.safetyNotes = safetyNotes
        self.isBrick = isBrick
        self.brickGroupID = brickGroupID
        self.isOptional = isOptional
    }
}
