import Foundation

/// The framework-neutral result of converting an Endurance session into a
/// structured, schedulable workout (§I).
///
/// The central requirement is honesty: a conversion that quietly drops intervals
/// is worse than no conversion at all, because the athlete would train the wrong
/// session believing it matched the plan. So every conversion states exactly
/// what survived, and `unsupported` is a first-class, non-failing outcome.
public struct WorkoutConversion: Codable, Sendable, Hashable, Identifiable {

    public enum Kind: String, Codable, Sendable, Hashable, CaseIterable {
        /// Every step, goal and target is representable.
        case exact
        /// Representable, but something was flattened or dropped. Requires
        /// explicit user confirmation before scheduling (§I).
        case simplified
        /// Not representable. Endurance keeps the full session; nothing is
        /// scheduled to the Workout app.
        case unsupported

        public var localizationKey: String { "conversion.\(rawValue)" }

        /// Only exact conversions may be scheduled without asking.
        public var requiresConfirmation: Bool { self == .simplified }
        public var isSchedulable: Bool { self != .unsupported }
    }

    /// What a conversion had to give up, stated concretely.
    public enum Warning: String, Codable, Sendable, Hashable, CaseIterable {
        case repeatsFlattened
        case nestedStepsFlattened
        case intensityTargetDropped
        case paceAlertUnsupported
        case powerAlertUnsupported
        case cadenceAlertUnsupported
        case openGoalApproximated
        case multisportTransitionsApproximated
        case distanceGoalConvertedToTime
        case customStepLabelsDropped

        public var localizationKey: String { "conversionwarning.\(rawValue)" }
    }

    public var id: UUID
    /// Always the Endurance identity — never a WorkoutKit id (§A: framework ids
    /// must not become the primary local identity).
    public var scheduledWorkoutID: UUID
    public var kind: Kind
    public var warnings: [Warning]
    /// Human-readable names of fields that could not be represented.
    public var unsupportedFields: [String]
    /// Incremented when converter behaviour changes, so previously scheduled
    /// workouts can be detected as stale and refreshed.
    public var conversionVersion: Int
    public var lastScheduledAt: Date?

    public init(
        id: UUID = UUID(),
        scheduledWorkoutID: UUID,
        kind: Kind,
        warnings: [Warning] = [],
        unsupportedFields: [String] = [],
        conversionVersion: Int = WorkoutConversion.currentVersion,
        lastScheduledAt: Date? = nil
    ) {
        self.id = id
        self.scheduledWorkoutID = scheduledWorkoutID
        self.kind = kind
        self.warnings = warnings
        self.unsupportedFields = unsupportedFields
        self.conversionVersion = conversionVersion
        self.lastScheduledAt = lastScheduledAt
    }

    /// Bump whenever conversion output changes meaningfully.
    public static let currentVersion = 1

    /// An exact conversion may never carry warnings — that combination would be
    /// a lie about fidelity, so it is normalized at construction.
    public static func exact(scheduledWorkoutID: UUID) -> WorkoutConversion {
        WorkoutConversion(scheduledWorkoutID: scheduledWorkoutID, kind: .exact)
    }

    public static func simplified(
        scheduledWorkoutID: UUID,
        warnings: [Warning],
        unsupportedFields: [String] = []
    ) -> WorkoutConversion {
        // A "simplified" conversion with nothing lost is really an exact one.
        guard !warnings.isEmpty || !unsupportedFields.isEmpty else {
            return .exact(scheduledWorkoutID: scheduledWorkoutID)
        }
        return WorkoutConversion(
            scheduledWorkoutID: scheduledWorkoutID,
            kind: .simplified,
            warnings: warnings,
            unsupportedFields: unsupportedFields)
    }

    public static func unsupported(
        scheduledWorkoutID: UUID,
        reason: [String]
    ) -> WorkoutConversion {
        WorkoutConversion(
            scheduledWorkoutID: scheduledWorkoutID,
            kind: .unsupported,
            unsupportedFields: reason)
    }

    /// True when a stored conversion predates the current converter.
    public var isStale: Bool { conversionVersion < Self.currentVersion }
}

/// The structured content a conversion reads: the plan's own step tree, lifted
/// out of `WorkoutTemplate` so the converter does not need the whole template.
public struct WorkoutStructure: Sendable, Hashable {
    public var warmup: [WorkoutStep]
    public var mainSet: [WorkoutStep]
    public var cooldown: [WorkoutStep]

    public init(warmup: [WorkoutStep], mainSet: [WorkoutStep], cooldown: [WorkoutStep]) {
        self.warmup = warmup
        self.mainSet = mainSet
        self.cooldown = cooldown
    }

    public var allSteps: [WorkoutStep] { warmup + mainSet + cooldown }
    public var isEmpty: Bool { allSteps.isEmpty }

    /// A session with no structured steps converts to a simple single-goal
    /// workout rather than an interval workout.
    public var isSingleGoal: Bool { isEmpty }

    /// Nested children are the main thing WorkoutKit cannot always express.
    public var hasNestedSteps: Bool { allSteps.contains { !$0.childSteps.isEmpty } }
    public var hasRepeats: Bool { allSteps.contains { $0.repeats > 1 } }
}
