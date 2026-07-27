import Foundation
import EnduranceDomain

/// Exactly what Endurance will write to HealthKit, decided before any HealthKit
/// object exists (§2).
///
/// The separation is the point. Everything contentious — which values are real,
/// which are absent, what provenance to declare — is settled here, in a value
/// type that can be asserted field by field on any machine. The adapter's job
/// shrinks to translating this into `HKWorkout`, which is the part that cannot
/// be unit-tested without a device.
///
/// The governing rule (§2): **never fabricate**. A manually logged session has
/// no heart rate, no power, and no route, and this payload has nowhere to put
/// them. Absence is represented by absence, not by a plausible zero.
public struct HealthWorkoutExportPayload: Sendable, Hashable {

    /// `HKWorkoutActivityType.rawValue` — see `HealthActivityMapping`.
    public var activityRawValue: UInt
    public var start: Date
    public var end: Date
    public var durationSeconds: Int

    /// Only present when genuinely known.
    public var distanceMeters: Double?
    public var activeEnergyKilocalories: Double?

    public var isIndoor: Bool?
    public var isOpenWater: Bool?

    /// Provenance, so a hand-typed session is never mistaken for a recorded one.
    public var wasUserEntered: Bool

    /// Endurance identity, written to metadata so a returning anchored import
    /// can be recognised as our own (§3).
    public var executionID: UUID
    public var scheduledWorkoutID: UUID?
    public var idempotencyKey: String
    public var exportVersion: Int
    public var schemaVersion: Int

    public init(
        activityRawValue: UInt,
        start: Date,
        end: Date,
        durationSeconds: Int,
        distanceMeters: Double? = nil,
        activeEnergyKilocalories: Double? = nil,
        isIndoor: Bool? = nil,
        isOpenWater: Bool? = nil,
        wasUserEntered: Bool,
        executionID: UUID,
        scheduledWorkoutID: UUID? = nil,
        idempotencyKey: String,
        exportVersion: Int = HealthExportRecord.currentVersion,
        schemaVersion: Int = HealthWorkoutExportPayload.currentSchemaVersion
    ) {
        self.activityRawValue = activityRawValue
        self.start = start
        self.end = end
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
        self.activeEnergyKilocalories = activeEnergyKilocalories
        self.isIndoor = isIndoor
        self.isOpenWater = isOpenWater
        self.wasUserEntered = wasUserEntered
        self.executionID = executionID
        self.scheduledWorkoutID = scheduledWorkoutID
        self.idempotencyKey = idempotencyKey
        self.exportVersion = exportVersion
        self.schemaVersion = schemaVersion
    }

    public static let currentSchemaVersion = 2

    /// Metadata keys written alongside the workout.
    ///
    /// Reverse-DNS namespaced so they cannot collide with Apple's own keys or
    /// another app's. These are what make orphan recovery possible: a workout
    /// saved but never linked locally can still be found by its execution id.
    public enum MetadataKey {
        public static let executionID = "com.example.endurance.executionID"
        public static let scheduledWorkoutID = "com.example.endurance.scheduledWorkoutID"
        public static let idempotencyKey = "com.example.endurance.idempotencyKey"
        public static let exportVersion = "com.example.endurance.exportVersion"
        public static let schemaVersion = "com.example.endurance.schemaVersion"

        public static let all: [String] = [
            executionID, scheduledWorkoutID, idempotencyKey, exportVersion, schemaVersion,
        ]
    }

    /// The metadata dictionary, as plain values. Apple's own keys (indoor,
    /// swimming location, user-entered) are added by the adapter using their
    /// documented constants; this covers Endurance's own identity.
    public var enduranceMetadata: [String: String] {
        var metadata: [String: String] = [
            MetadataKey.executionID: executionID.uuidString,
            MetadataKey.idempotencyKey: idempotencyKey,
            MetadataKey.exportVersion: String(exportVersion),
            MetadataKey.schemaVersion: String(schemaVersion),
        ]
        if let scheduledWorkoutID {
            metadata[MetadataKey.scheduledWorkoutID] = scheduledWorkoutID.uuidString
        }
        return metadata
    }

    /// Recover the execution identity from metadata read back out of HealthKit,
    /// which is how an orphaned export is reconnected (§9).
    public static func executionID(fromMetadata metadata: [String: Any]?) -> UUID? {
        guard let raw = metadata?[MetadataKey.executionID] as? String else { return nil }
        return UUID(uuidString: raw)
    }
}

// MARK: - Building

public enum HealthExportPayloadBuilder {

    public enum BuildError: Error, Sendable, Equatable {
        case notEligible(ExportEligibility)
        case unmappableSport(Sport)
    }

    /// Build the payload for an execution, or explain why it cannot be built.
    ///
    /// Eligibility is re-checked here rather than trusted from the caller: this
    /// is the last point before data reaches the athlete's Health record, and a
    /// caller that forgot to check would otherwise write a duplicate.
    public static func build(
        for input: ExportEvaluationInput,
        isIndoor: Bool? = nil,
        isOpenWater: Bool? = nil
    ) throws -> HealthWorkoutExportPayload {

        let eligibility = ExportEligibilityEvaluator.evaluate(input)
        guard eligibility.canExportNow else {
            throw BuildError.notEligible(eligibility)
        }
        guard let activity = HealthActivityMapping.activityRawValue(for: input.sport) else {
            throw BuildError.unmappableSport(input.sport)
        }

        let execution = input.execution
        let end = execution.start.addingTimeInterval(TimeInterval(execution.durationSeconds))

        return HealthWorkoutExportPayload(
            activityRawValue: activity,
            start: execution.start,
            end: end,
            durationSeconds: execution.durationSeconds,
            // Only carried when the athlete actually supplied them. A nil here
            // becomes an absent HealthKit quantity, not a zero.
            distanceMeters: execution.distanceMeters.flatMap { $0 > 0 ? $0 : nil },
            activeEnergyKilocalories: execution.activeEnergyKilocalories.flatMap { $0 > 0 ? $0 : nil },
            isIndoor: isIndoor,
            isOpenWater: isOpenWater,
            // Both eligible sources are hand-logged or in-app timed, never
            // sensor-recorded — so this is always true in Stage 3. It becomes
            // meaningful when the watch records workouts in Stage 5/6.
            wasUserEntered: execution.source == .manual,
            executionID: execution.id,
            scheduledWorkoutID: execution.scheduledWorkoutID,
            idempotencyKey: HealthExportRecord.idempotencyKey(for: execution.id))
    }
}

// MARK: - Ownership

/// Guards every destructive HealthKit operation (§7).
///
/// Endurance may only delete or replace records it created. Deleting another
/// app's workout would be destroying data the athlete never gave us
/// responsibility for, so ownership is checked against the saved record rather
/// than inferred from a match.
public enum HealthOwnership {

    /// `Result`'s failure type must be an `Error`, and this doubles as a value
    /// the UI can explain rather than a bare bool.
    public enum DeletionRefusal: String, Error, Sendable, Hashable {
        case notEnduranceOwned
        case noProviderReference
        case importedNotExported

        public var localizationKey: String { "deleterefusal.\(rawValue)" }
    }

    /// Whether Endurance may delete this HealthKit object.
    public static func mayDelete(_ record: HealthExportRecord?) -> Result<String, DeletionRefusal> {
        guard let record else { return .failure(.noProviderReference) }
        guard record.isEnduranceOwned else { return .failure(.notEnduranceOwned) }
        guard let providerID = record.providerWorkoutID else { return .failure(.noProviderReference) }
        guard record.status == .saved || record.status == .replacing else {
            return .failure(.noProviderReference)
        }
        return .success(providerID)
    }

    /// Whether an *imported* activity may be deleted from Health. It may not:
    /// the source app owns it, and unmatching it locally says nothing about
    /// whether the athlete wants it gone from Health (§7).
    public static func mayDeleteImported() -> Bool { false }
}
