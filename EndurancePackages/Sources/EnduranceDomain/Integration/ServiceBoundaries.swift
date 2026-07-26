import Foundation

/// The Release 2 integration boundaries (§B).
///
/// Every protocol here is expressed purely in domain types. HealthKit,
/// WorkoutKit, ActivityKit, WidgetKit and WatchConnectivity live *behind* these,
/// in their own packages, and map inwards. Two consequences that matter:
///
///   * The core stays testable without a device, an entitlement, or Xcode.
///   * A framework that changes shape — or is denied at runtime — cannot reach
///     into scheduling, matching, or progress logic.
///
/// Each boundary has a test-only implementation in the test target. Production
/// code never fakes framework success (§T).

// MARK: - Health

/// Reads completed activities from the system health store.
public protocol HealthWorkoutImporting: Sendable {
    /// Whether the platform can provide health data at all (§P).
    var isHealthDataAvailable: Bool { get }

    /// Request only the capabilities a visible feature uses (§C).
    func requestAuthorization(for capabilities: [HealthCapability]) async throws -> [HealthCapabilityState]

    /// Current per-capability state. Never a single global boolean (§C).
    func authorizationStates(for capabilities: [HealthCapability]) async -> [HealthCapabilityState]

    /// Incremental import from a persisted cursor (§D). Returns new/updated
    /// activities, deletions, and the advanced cursor.
    func importWorkouts(since cursor: ImportCursor) async throws -> HealthImportBatch
}

/// Writes Endurance-created workouts to the system health store.
public protocol HealthWorkoutExporting: Sendable {
    func requestWriteAuthorization() async throws -> [HealthCapabilityState]

    /// Save an execution. Returns the provider identifier for de-duplication.
    /// Implementations must refuse ineligible executions rather than silently
    /// skipping them, so the caller can surface an accurate state (§F).
    func export(_ execution: WorkoutExecution, title: String) async throws -> String

    /// HealthKit samples are immutable; an "edit" is delete + re-save. The
    /// adapter documents and performs whichever the platform supports (§F).
    func replaceExport(providerID: String, with execution: WorkoutExecution, title: String) async throws -> String

    /// Remove only samples Endurance itself wrote (§Q).
    func deleteExport(providerID: String) async throws
}

/// One incremental import.
public struct HealthImportBatch: Sendable, Hashable {
    public var summaries: [ExternalWorkoutSummary]
    /// Provider ids deleted at source since the last import.
    public var deletedProviderIDs: [String]
    public var updatedCursor: ImportCursor

    public init(
        summaries: [ExternalWorkoutSummary],
        deletedProviderIDs: [String] = [],
        updatedCursor: ImportCursor
    ) {
        self.summaries = summaries
        self.deletedProviderIDs = deletedProviderIDs
        self.updatedCursor = updatedCursor
    }
}

/// A health capability the app may request. Framework-neutral so the domain can
/// reason about, persist, and display authorization without importing HealthKit.
public enum HealthCapability: String, Codable, Sendable, Hashable, CaseIterable {
    case workouts
    case heartRate
    case restingHeartRate
    case runningDistance
    case cyclingDistance
    case swimmingDistance
    case activeEnergy
    case cyclingPower
    case runningPower
    case workoutRoute

    public var localizationKey: String { "healthcap.\(rawValue)" }

    /// Whether Endurance ever writes this. Everything else is read-only, and
    /// §C forbids requesting write access "for future use".
    public var isWritable: Bool {
        switch self {
        case .workouts, .workoutRoute, .activeEnergy: return true
        default: return false
        }
    }
}

// MARK: - WorkoutKit

/// Converts an Endurance session into a schedulable structured workout.
public protocol WorkoutKitConverting: Sendable {
    func convert(_ workout: ScheduledWorkout, template: WorkoutTemplate?) -> WorkoutKitConversionResult
}

/// Schedules converted workouts onto the Watch's Workout app.
public protocol WorkoutScheduling: Sendable {
    var isSupported: Bool { get }
    func authorizationState() async -> WorkoutSchedulingAuthorization
    func requestAuthorization() async -> WorkoutSchedulingAuthorization
    func schedule(_ request: WorkoutKitScheduleRequest) async throws
    func remove(_ request: WorkoutKitScheduleRequest) async throws
    /// The app-owned system schedule, used to reconcile a previous successful
    /// framework call whose local transaction did not finish.
    func scheduledPlans() async throws -> [WorkoutKitScheduledPlan]
    func removeAllEndurancePlans() async throws
}

public enum WorkoutSchedulingAuthorization: String, Codable, Sendable, Hashable {
    case notDetermined
    case authorized
    case denied
    case restricted
    case unavailable

    public var localizationKey: String { "wkauth.\(rawValue)" }
}

/// A framework-free scheduling command. `workoutPlanID` is deterministic from
/// the Endurance scheduled-workout ID + conversion version; it is intentionally
/// not an execution or HealthKit identifier.
public struct WorkoutKitScheduleRequest: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID { workoutPlanID }
    public var workoutPlanID: UUID
    public var scheduledWorkoutID: UUID
    public var plannedStart: Date
    public var conversion: WorkoutKitConversionResult

    public init(workoutPlanID: UUID, scheduledWorkoutID: UUID, plannedStart: Date,
                conversion: WorkoutKitConversionResult) {
        self.workoutPlanID = workoutPlanID
        self.scheduledWorkoutID = scheduledWorkoutID
        self.plannedStart = plannedStart
        self.conversion = conversion
    }
}

public struct WorkoutKitScheduledPlan: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID { workoutPlanID }
    public var workoutPlanID: UUID
    public var plannedStart: Date
    public var isComplete: Bool

    public init(workoutPlanID: UUID, plannedStart: Date, isComplete: Bool = false) {
        self.workoutPlanID = workoutPlanID
        self.plannedStart = plannedStart
        self.isComplete = isComplete
    }
}

// MARK: - Active workout

/// Drives a live workout session. On watchOS this wraps `HKWorkoutSession` and
/// `HKLiveWorkoutBuilder`; in tests it is a deterministic fake.
public protocol ActiveWorkoutManaging: AnyObject, Sendable {
    var state: ActiveWorkoutState { get }
    func prepare(for workout: ScheduledWorkout) async throws
    func start() async throws
    func pause() async throws
    func resume() async throws
    func end() async throws
    func save() async throws -> WorkoutExecution
    func discard() async throws
    func markLap() async
}

// MARK: - Watch synchronization

/// Durable, idempotent transfer between phone and watch (§H).
public protocol WatchWorkoutSyncing: Sendable {
    var isPaired: Bool { get }
    var isWatchAppInstalled: Bool { get }
    var isReachable: Bool { get }

    /// Send an upcoming window of planned sessions.
    func sendPlannedWindow(_ workouts: [ScheduledWorkout]) async throws

    /// Queue a completion for delivery; safe to call repeatedly with the same
    /// execution (§O — retries must not duplicate).
    func enqueueCompletion(_ execution: WorkoutExecution) async throws

    /// Completions received from the counterpart device, de-duplicated by
    /// execution id and external key.
    func pendingCompletions() async -> [WorkoutExecution]

    func acknowledge(executionIDs: [UUID]) async
}

// MARK: - Live Activities

public protocol LiveActivityManaging: Sendable {
    var isSupported: Bool { get }
    var areActivitiesEnabled: Bool { get }
    func start(for workout: ScheduledWorkout, execution: UUID) async throws
    func update(elapsed: TimeInterval, state: ActiveWorkoutState, primaryMetric: String?) async
    func end(reason: LiveActivityEndReason) async
}

public enum LiveActivityEndReason: String, Sendable, Hashable {
    case saved, discarded, failed, recoveredStale
}

// MARK: - Widgets

/// Supplies the compact snapshot widgets and intents read (§K). Deliberately
/// narrow: extensions must never open the full store on every timeline refresh.
public protocol TodaySnapshotProviding: Sendable {
    func currentSnapshot() -> SharedTodaySnapshot?
    func write(_ snapshot: SharedTodaySnapshot)
}

// MARK: - Records

/// What was scheduled into the Workout app, and whether it is still current.
public struct WorkoutKitScheduleRecord: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var scheduledWorkoutID: UUID
    public var templateID: UUID?
    /// Deterministic `WorkoutPlan.id`, not a HealthKit UUID or execution ID.
    public var schedulingIdentifier: String
    public var conversionOutcome: WorkoutKitConversionOutcome
    /// Bumped when the converter's behaviour changes, so stale schedules can be
    /// detected and refreshed rather than silently diverging.
    public var conversionVersion: Int
    public var conversionFingerprint: String
    public var originalPlannedStart: Date
    public var lastScheduledStart: Date
    public var status: WorkoutKitScheduleStatus
    public var lastSynchronization: Date?
    public var warnings: [WorkoutKitConversionWarning]
    public var parentBrickGroupID: UUID?
    public var componentScheduledWorkoutIDs: [UUID]
    public var schedulingOrder: Int
    public var lastFailure: WorkoutKitFailureCategory?
    public var retryCount: Int
    public var removedAt: Date?
    /// An athlete approved this exact conversion fingerprint. An unrelated
    /// future simplification still needs a fresh confirmation.
    public var userConfirmedSimplification: Bool

    public init(
        id: UUID = UUID(),
        scheduledWorkoutID: UUID,
        schedulingIdentifier: String,
        templateID: UUID? = nil,
        conversionOutcome: WorkoutKitConversionOutcome,
        conversionVersion: Int,
        conversionFingerprint: String,
        originalPlannedStart: Date,
        lastScheduledStart: Date,
        status: WorkoutKitScheduleStatus,
        lastSynchronization: Date? = nil,
        warnings: [WorkoutKitConversionWarning] = [],
        parentBrickGroupID: UUID? = nil,
        componentScheduledWorkoutIDs: [UUID] = [],
        schedulingOrder: Int = 0,
        lastFailure: WorkoutKitFailureCategory? = nil,
        retryCount: Int = 0,
        removedAt: Date? = nil,
        userConfirmedSimplification: Bool = false
    ) {
        self.id = id
        self.scheduledWorkoutID = scheduledWorkoutID
        self.templateID = templateID
        self.schedulingIdentifier = schedulingIdentifier
        self.conversionOutcome = conversionOutcome
        self.conversionVersion = conversionVersion
        self.conversionFingerprint = conversionFingerprint
        self.originalPlannedStart = originalPlannedStart
        self.lastScheduledStart = lastScheduledStart
        self.status = status
        self.lastSynchronization = lastSynchronization
        self.warnings = warnings
        self.parentBrickGroupID = parentBrickGroupID
        self.componentScheduledWorkoutIDs = componentScheduledWorkoutIDs
        self.schedulingOrder = schedulingOrder
        self.lastFailure = lastFailure
        self.retryCount = retryCount
        self.removedAt = removedAt
        self.userConfirmedSimplification = userConfirmedSimplification
    }

    public var workoutPlanID: UUID? { UUID(uuidString: schedulingIdentifier) }
    public var isStale: Bool {
        status == .stale || conversionVersion < WorkoutKitConversionResult.currentVersion
    }
}

/// A durable record of an integration failure, so the UI can explain what
/// happened and what was preserved (§P) without surfacing raw framework text.
public struct IntegrationErrorRecord: Codable, Sendable, Hashable, Identifiable {
    public enum Area: String, Codable, Sendable {
        case healthImport, healthExport, workoutKit, watchSync, activeWorkout, liveActivity, migration
    }
    public var id: UUID
    public var area: Area
    public var occurredAt: Date
    /// A stable, non-sensitive code — never a raw framework message, and never
    /// anything derived from health values (§Q).
    public var code: String
    public var isRecoverable: Bool

    public init(
        id: UUID = UUID(),
        area: Area,
        occurredAt: Date = Date(),
        code: String,
        isRecoverable: Bool
    ) {
        self.id = id
        self.area = area
        self.occurredAt = occurredAt
        self.code = code
        self.isRecoverable = isRecoverable
    }
}
