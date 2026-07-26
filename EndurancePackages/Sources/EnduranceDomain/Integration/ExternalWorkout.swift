import Foundation

/// Release 2 integration vocabulary.
///
/// Everything here is Foundation-only by design (§B): HealthKit, WorkoutKit,
/// ActivityKit and WidgetKit types must never reach the core domain. Adapters in
/// the framework-specific packages map *into* these types, so matching,
/// duplicate prevention and progress logic stay testable without a device — and
/// without Xcode.

// MARK: - Provider

/// Where an external activity came from. Deliberately not an open string, so a
/// typo cannot create a second identity space for the same provider.
public enum WorkoutProvider: String, Codable, Sendable, Hashable, CaseIterable {
    case healthKit
    case appleWatch
    case workoutKit
    /// Reserved for Release 4 (Garmin, Strava). Present so the identity model
    /// does not change shape when those arrive (§28.2).
    case garmin
    case strava

    public var localizationKey: String { "provider.\(rawValue)" }
}

/// A summarized external activity, imported from a provider.
///
/// This is a *summary*, not a sample store: §N is explicit that high-frequency
/// live data belongs in HealthKit, not duplicated into SwiftData. We keep only
/// what offline display, matching, progress, conflict resolution and export
/// actually need.
public struct ExternalWorkoutSummary: Codable, Sendable, Hashable, Identifiable {
    /// Local identity for this record. Never the provider's id — the provider id
    /// is a *reference*, so a provider changing ids cannot orphan local state.
    public var id: UUID
    public var provider: WorkoutProvider
    /// The provider's own identifier (e.g. an `HKWorkout.uuid` string).
    public var providerWorkoutID: String
    public var sourceBundleIdentifier: String?
    public var sourceName: String?
    public var deviceName: String?

    public var sport: Sport
    public var start: Date
    public var end: Date
    public var durationSeconds: Int
    public var distanceMeters: Double?
    public var activeEnergyKilocalories: Double?
    public var averageHeartRate: Double?
    public var maximumHeartRate: Double?
    public var averageCyclingPowerWatts: Double?
    public var averageRunningPowerWatts: Double?
    public var isIndoor: Bool?
    public var isOpenWater: Bool?
    public var hasRoute: Bool

    public var importedAt: Date
    public var lastObservedAt: Date
    /// Provider-side revision marker, where the provider exposes one. Used to
    /// detect edits without re-reading every field.
    public var sourceRevision: String?
    public var isDeletedAtSource: Bool

    public init(
        id: UUID = UUID(),
        provider: WorkoutProvider,
        providerWorkoutID: String,
        sourceBundleIdentifier: String? = nil,
        sourceName: String? = nil,
        deviceName: String? = nil,
        sport: Sport,
        start: Date,
        end: Date,
        durationSeconds: Int,
        distanceMeters: Double? = nil,
        activeEnergyKilocalories: Double? = nil,
        averageHeartRate: Double? = nil,
        maximumHeartRate: Double? = nil,
        averageCyclingPowerWatts: Double? = nil,
        averageRunningPowerWatts: Double? = nil,
        isIndoor: Bool? = nil,
        isOpenWater: Bool? = nil,
        hasRoute: Bool = false,
        importedAt: Date,
        lastObservedAt: Date,
        sourceRevision: String? = nil,
        isDeletedAtSource: Bool = false
    ) {
        self.id = id
        self.provider = provider
        self.providerWorkoutID = providerWorkoutID
        self.sourceBundleIdentifier = sourceBundleIdentifier
        self.sourceName = sourceName
        self.deviceName = deviceName
        self.sport = sport
        self.start = start
        self.end = end
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
        self.activeEnergyKilocalories = activeEnergyKilocalories
        self.averageHeartRate = averageHeartRate
        self.maximumHeartRate = maximumHeartRate
        self.averageCyclingPowerWatts = averageCyclingPowerWatts
        self.averageRunningPowerWatts = averageRunningPowerWatts
        self.isIndoor = isIndoor
        self.isOpenWater = isOpenWater
        self.hasRoute = hasRoute
        self.importedAt = importedAt
        self.lastObservedAt = lastObservedAt
        self.sourceRevision = sourceRevision
        self.isDeletedAtSource = isDeletedAtSource
    }

    /// The idempotency key for duplicate prevention (§O). Two observations of
    /// the same execution — however they reach us — collapse onto this.
    public var idempotencyKey: String {
        "\(provider.rawValue):\(providerWorkoutID)"
    }

    public var durationMinutes: Int { max(0, durationSeconds / 60) }
}

// MARK: - Execution

/// How a completed session was actually performed, as opposed to how it was
/// planned. Separate from `WorkoutCompletion` because one scheduled workout can
/// be executed once but *observed* through several frameworks.
public struct WorkoutExecution: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    /// The scheduled workout this execution belongs to, when matched.
    public var scheduledWorkoutID: UUID?
    public var source: CompletionSource
    public var start: Date
    public var durationSeconds: Int
    public var distanceMeters: Double?
    public var averageHeartRate: Double?
    public var activeEnergyKilocalories: Double?
    /// External observations of this same execution, keyed by idempotency key.
    public var externalKeys: Set<String>
    /// The HealthKit object we wrote, if Endurance exported this execution.
    public var exportedProviderID: String?
    public var recordedAt: Date

    public init(
        id: UUID = UUID(),
        scheduledWorkoutID: UUID? = nil,
        source: CompletionSource,
        start: Date,
        durationSeconds: Int,
        distanceMeters: Double? = nil,
        averageHeartRate: Double? = nil,
        activeEnergyKilocalories: Double? = nil,
        externalKeys: Set<String> = [],
        exportedProviderID: String? = nil,
        recordedAt: Date = Date()
    ) {
        self.id = id
        self.scheduledWorkoutID = scheduledWorkoutID
        self.source = source
        self.start = start
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
        self.averageHeartRate = averageHeartRate
        self.activeEnergyKilocalories = activeEnergyKilocalories
        self.externalKeys = externalKeys
        self.exportedProviderID = exportedProviderID
        self.recordedAt = recordedAt
    }

    /// An execution that originated outside Endurance must never be exported
    /// back to its own source (§F: "never re-export imported workouts").
    public var isEligibleForHealthExport: Bool {
        guard exportedProviderID == nil else { return false }
        switch source {
        case .manual, .appTimer:
            return true
        case .healthKit, .appleWatch, .external:
            return false
        }
    }
}

// MARK: - Import cursor

/// Where an incremental import got to, so the app never rescans the whole store
/// (§D). The anchor itself is provider-opaque; we hold it as data.
public struct ImportCursor: Codable, Sendable, Hashable {
    public var provider: WorkoutProvider
    public var anchorData: Data?
    public var lastSuccessfulImport: Date?
    public var lastAttempt: Date?
    public var lastErrorDescription: String?

    public init(
        provider: WorkoutProvider,
        anchorData: Data? = nil,
        lastSuccessfulImport: Date? = nil,
        lastAttempt: Date? = nil,
        lastErrorDescription: String? = nil
    ) {
        self.provider = provider
        self.anchorData = anchorData
        self.lastSuccessfulImport = lastSuccessfulImport
        self.lastAttempt = lastAttempt
        self.lastErrorDescription = lastErrorDescription
    }
}

// MARK: - Health authorization

/// Per-capability authorization state.
///
/// §C forbids a single global "HealthKit authorized" boolean, and HealthKit
/// genuinely cannot report read authorization — `authorizationStatus(for:)`
/// describes *write* only. `readAuthorizationIsUnknowable` encodes that honestly
/// rather than guessing.
public struct HealthCapabilityState: Codable, Sendable, Hashable {
    public enum Access: String, Codable, Sendable { case read, write }
    public enum Status: String, Codable, Sendable {
        case notDetermined
        case denied
        case authorized
        /// Requested, but the platform will not tell us whether reads are
        /// permitted. Treated as "ask and see what arrives".
        case unknowable
    }

    public var capability: String
    public var access: Access
    public var status: Status

    public init(capability: String, access: Access, status: Status) {
        self.capability = capability
        self.access = access
        self.status = status
    }
}
