import Foundation

/// A fitness data provider we can import from / export to. Kept in the domain so
/// external references have a stable, portable representation that survives
/// iCloud sync and export/import (§28.2, §28.14, §28.15).
public enum FitnessProviderID: String, Codable, Sendable, Hashable, CaseIterable {
    case healthKit
    case appleWatch
    case workoutKit
    case garmin
    case strava
    case manual
}

/// A reference to the "same" workout in an external system. Recording the
/// provider identifier + timestamps is what lets us detect duplicates and edited
/// or deleted upstream activities without re-importing (§28.3, §28.14).
public struct ExternalWorkoutReference: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var provider: FitnessProviderID
    /// The provider's own identifier for the activity (e.g. HKWorkout.uuid,
    /// Strava activity id). Never a title+date composite.
    public var providerActivityID: String
    public var importedAt: Date
    public var lastSyncedAt: Date?
    /// Provider revision/update timestamp where available, to detect edits.
    public var sourceRevision: String?

    public init(
        id: UUID = UUID(),
        provider: FitnessProviderID,
        providerActivityID: String,
        importedAt: Date,
        lastSyncedAt: Date? = nil,
        sourceRevision: String? = nil
    ) {
        self.id = id
        self.provider = provider
        self.providerActivityID = providerActivityID
        self.importedAt = importedAt
        self.lastSyncedAt = lastSyncedAt
        self.sourceRevision = sourceRevision
    }
}

/// Stable, layered identity for a planned/completed workout that must survive
/// rescheduling, sync, HealthKit/watch/Garmin/Strava import, plan updates,
/// device replacement, and export/re-import (§28.2). Distinct IDs for each
/// concern so a change in one doesn't invalidate the others.
public struct WorkoutIdentity: Codable, Sendable, Hashable {
    /// Plan the workout came from (nil for ad-hoc/imported sessions).
    public var planID: UUID?
    /// Immutable plan template (nil for imported/ad-hoc sessions).
    public var templateID: UUID?
    /// The scheduled instance — the durable anchor for user state.
    public var scheduledWorkoutID: UUID
    /// A specific execution (a watch session, a manual log). Nil until executed.
    public var executionID: UUID?
    /// Links to external systems.
    public var externalReferences: [ExternalWorkoutReference]

    public init(
        planID: UUID? = nil,
        templateID: UUID? = nil,
        scheduledWorkoutID: UUID,
        executionID: UUID? = nil,
        externalReferences: [ExternalWorkoutReference] = []
    ) {
        self.planID = planID
        self.templateID = templateID
        self.scheduledWorkoutID = scheduledWorkoutID
        self.executionID = executionID
        self.externalReferences = externalReferences
    }
}
