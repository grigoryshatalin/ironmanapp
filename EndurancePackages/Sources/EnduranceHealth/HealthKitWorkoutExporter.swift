import Foundation
import EnduranceDomain

#if canImport(HealthKit)
import HealthKit

/// Writes Endurance-created workouts to HealthKit (§2, §6).
///
/// Uses `HKWorkoutBuilder` rather than the `HKWorkout` initialisers, which Apple
/// deprecated in iOS 17 — see `DECISIONS.md`. The builder is also the honest
/// shape for this job: samples are *added*, so a session with no distance simply
/// contributes no distance sample, rather than a zero that would look measured.
///
/// This type translates an already-decided `HealthWorkoutExportPayload`. It
/// makes no eligibility judgements of its own; those are settled in
/// `ExportEligibilityEvaluator`, which is testable without a device.
public final class HealthKitWorkoutExporter: @unchecked Sendable {

    private let store: HKHealthStore

    public init() {
        self.store = HKHealthStore()
    }

    public var isHealthDataAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    // MARK: - Authorization

    /// Write authorization only — requested when the athlete enables export (§4).
    public func requestWriteAuthorization() async throws -> [HealthCapabilityState] {
        guard isHealthDataAvailable else { throw HealthExportError.healthDataUnavailable }

        let types: Set<HKSampleType> = [
            HKObjectType.workoutType(),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.distanceWalkingRunning),
            HKQuantityType(.distanceCycling),
            HKQuantityType(.distanceSwimming),
        ]
        try await store.requestAuthorization(toShare: types, read: [])
        return writeAuthorizationStates()
    }

    /// Unlike reads, write authorization *is* knowable, so this reports a real
    /// status rather than `.unknowable` (§C, §4).
    public func writeAuthorizationStates() -> [HealthCapabilityState] {
        HealthCapabilityPlan.export.map { capability in
            let status: HealthCapabilityState.Status
            switch capability {
            case .workouts:
                status = Self.map(store.authorizationStatus(for: HKObjectType.workoutType()))
            case .activeEnergy:
                status = Self.map(store.authorizationStatus(for: HKQuantityType(.activeEnergyBurned)))
            default:
                status = .notDetermined
            }
            return HealthCapabilityState(
                capability: capability.rawValue, access: .write, status: status)
        }
    }

    private static func map(_ status: HKAuthorizationStatus) -> HealthCapabilityState.Status {
        switch status {
        case .sharingAuthorized: return .authorized
        case .sharingDenied: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .notDetermined
        }
    }

    private var canWriteWorkouts: Bool {
        store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized
    }

    // MARK: - Save

    /// Save a payload and return the HealthKit object identifier.
    ///
    /// The returned id is what makes the export idempotent: the caller persists
    /// it, and both the eligibility evaluator and the anchored importer use it to
    /// recognise this workout as ours.
    public func save(_ payload: HealthWorkoutExportPayload) async throws -> String {
        guard isHealthDataAvailable else { throw HealthExportError.healthDataUnavailable }
        guard canWriteWorkouts else { throw HealthExportError.authorizationDenied }
        guard payload.end > payload.start else { throw HealthExportError.invalidDuration }
        guard let activity = HKWorkoutActivityType(rawValue: payload.activityRawValue) else {
            throw HealthExportError.unsupportedActivity
        }

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = activity
        if let isOpenWater = payload.isOpenWater, activity == .swimming {
            configuration.swimmingLocationType = isOpenWater ? .openWater : .pool
        }
        if let isIndoor = payload.isIndoor {
            configuration.locationType = isIndoor ? .indoor : .outdoor
        }

        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: nil)

        do {
            try await builder.beginCollection(at: payload.start)
            try await addSamples(payload, to: builder, activity: activity)
            try await builder.addMetadata(metadata(for: payload))
            try await builder.endCollection(at: payload.end)

            guard let workout = try await builder.finishWorkout() else {
                throw HealthExportError.saveFailed
            }
            return workout.uuid.uuidString
        } catch let error as HealthExportError {
            throw error
        } catch {
            // Never surface a raw HKError to the UI or the log (§8, §Q).
            throw HealthExportError.saveFailed
        }
    }

    /// Only genuinely known values become samples. A nil contributes nothing —
    /// there is deliberately no path here that invents a quantity (§2).
    private func addSamples(
        _ payload: HealthWorkoutExportPayload,
        to builder: HKWorkoutBuilder,
        activity: HKWorkoutActivityType
    ) async throws {
        var samples: [HKSample] = []

        if let meters = payload.distanceMeters, meters > 0,
           let type = Self.distanceType(for: activity) {
            samples.append(HKQuantitySample(
                type: type,
                quantity: HKQuantity(unit: .meter(), doubleValue: meters),
                start: payload.start,
                end: payload.end))
        }

        if let kilocalories = payload.activeEnergyKilocalories, kilocalories > 0 {
            samples.append(HKQuantitySample(
                type: HKQuantityType(.activeEnergyBurned),
                quantity: HKQuantity(unit: .kilocalorie(), doubleValue: kilocalories),
                start: payload.start,
                end: payload.end))
        }

        guard !samples.isEmpty else { return }
        try await builder.addSamples(samples)
    }

    private static func distanceType(for activity: HKWorkoutActivityType) -> HKQuantityType? {
        switch activity {
        case .running, .walking: return HKQuantityType(.distanceWalkingRunning)
        case .cycling: return HKQuantityType(.distanceCycling)
        case .swimming: return HKQuantityType(.distanceSwimming)
        default: return nil
        }
    }

    /// Apple's documented provenance keys plus Endurance's own identity.
    private func metadata(for payload: HealthWorkoutExportPayload) -> [String: Any] {
        var metadata: [String: Any] = payload.enduranceMetadata

        // The distinction §2 requires: a hand-logged session must never look
        // sensor-recorded.
        metadata[HKMetadataKeyWasUserEntered] = payload.wasUserEntered

        if let isIndoor = payload.isIndoor {
            metadata[HKMetadataKeyIndoorWorkout] = isIndoor
        }
        if let isOpenWater = payload.isOpenWater {
            metadata[HKMetadataKeySwimmingLocationType] =
                (isOpenWater ? HKWorkoutSwimmingLocationType.openWater
                             : HKWorkoutSwimmingLocationType.pool).rawValue
        }
        return metadata
    }

    // MARK: - Replace and delete

    /// HealthKit samples are immutable: an "edit" is a delete followed by a new
    /// save (§6). Ordering is deliberate — save first, then delete the old one —
    /// so a failure leaves a duplicate (visible and fixable) rather than a hole.
    public func replace(
        providerWorkoutID: String,
        with payload: HealthWorkoutExportPayload
    ) async throws -> String {
        let newID = try await save(payload)
        do {
            try await delete(providerWorkoutID: providerWorkoutID)
        } catch {
            // The new record exists; report so the caller can reconcile rather
            // than believing the replacement fully succeeded.
            throw HealthExportError.replacementFailed(newProviderID: newID)
        }
        return newID
    }

    /// Delete a workout Endurance created. Ownership is verified by the caller
    /// via `HealthOwnership`, and re-verified here against HealthKit's own record
    /// of the source — Endurance must never delete another app's data (§7).
    public func delete(providerWorkoutID: String) async throws {
        guard isHealthDataAvailable else { throw HealthExportError.healthDataUnavailable }
        guard let uuid = UUID(uuidString: providerWorkoutID) else {
            throw HealthExportError.deleteFailed
        }

        let workout = try await fetchWorkout(uuid: uuid)
        guard let workout else { return } // already gone; nothing to do

        guard workout.sourceRevision.source.bundleIdentifier == Bundle.main.bundleIdentifier else {
            throw HealthExportError.externallyOwnedCannotModify
        }

        do {
            try await store.delete(workout)
        } catch {
            throw HealthExportError.deleteFailed
        }
    }

    private func fetchWorkout(uuid: UUID) async throws -> HKWorkout? {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: HKQuery.predicateForObject(with: uuid),
                limit: 1,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: samples?.first as? HKWorkout)
                }
            }
            store.execute(query)
        }
    }

    // MARK: - Orphan recovery

    /// Find a workout we saved but never managed to link locally (§9).
    ///
    /// Without this, a crash between HealthKit's save and our own persistence
    /// would leave a workout in Health that Endurance can neither see nor avoid
    /// duplicating. The execution id in metadata is what makes it findable.
    public func findExportedWorkout(executionID: UUID) async throws -> String? {
        guard isHealthDataAvailable else { return nil }

        let predicate = HKQuery.predicateForObjects(
            withMetadataKey: HealthWorkoutExportPayload.MetadataKey.executionID,
            allowedValues: [executionID.uuidString])

        let workouts: [HKWorkout] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: 1,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: (samples as? [HKWorkout]) ?? [])
                }
            }
            store.execute(query)
        }
        return workouts.first?.uuid.uuidString
    }
}

#endif

/// Typed export failures (§8). Deliberately free of framework text so nothing
/// raw reaches the UI or the log.
public enum HealthExportError: Error, Sendable, Equatable {
    case healthDataUnavailable
    case authorizationDenied
    case authorizationNotDetermined
    case unsupportedActivity
    case unsupportedMultisport
    case missingDates
    case invalidDuration
    case duplicatePrevented
    case saveFailed
    case deleteFailed
    case persistenceFailedAfterSave(providerWorkoutID: String)
    /// The new record saved but the old one could not be removed.
    case replacementFailed(newProviderID: String)
    case externallyOwnedCannotModify
    case cancelled

    public var category: ExportFailureCategory {
        switch self {
        case .healthDataUnavailable: return .healthDataUnavailable
        case .authorizationDenied: return .authorizationDenied
        case .authorizationNotDetermined: return .authorizationNotDetermined
        case .unsupportedActivity, .unsupportedMultisport: return .unsupportedActivity
        case .missingDates: return .missingDates
        case .invalidDuration: return .invalidDuration
        case .duplicatePrevented: return .duplicatePrevented
        case .saveFailed: return .saveFailed
        case .deleteFailed, .externallyOwnedCannotModify: return .deleteFailed
        case .persistenceFailedAfterSave: return .persistenceFailedAfterSave
        case .replacementFailed: return .replacementFailed
        case .cancelled: return .cancelled
        }
    }

    /// A stable, non-sensitive log code. Never includes a HealthKit UUID (§Q).
    public var logCode: String { "export.\(category.rawValue)" }
}
