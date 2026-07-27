import Foundation
import EnduranceDomain

#if canImport(HealthKit)
import HealthKit

/// The real HealthKit adapter behind `HealthWorkoutImporting` (§D).
///
/// Everything framework-specific is confined here. The decisions — what counts
/// as a duplicate, what may be auto-matched, what is worth surfacing — live in
/// `ImportReconciler`, `WorkoutMatcher` and `HealthActivityMapping`, which are
/// HealthKit-free and therefore tested on the host. This type's job is narrow:
/// talk to HealthKit, and map what comes back into domain values.
///
/// Import is **incremental** via `HKAnchoredObjectQuery`: the anchor is
/// persisted, so the app never rescans the whole store on launch. HealthKit
/// hands back both new/changed samples and deletions in one pass, which is
/// exactly what `HealthImportBatch` carries.
public final class HealthKitWorkoutImporter: HealthWorkoutImporting, @unchecked Sendable {

    private let store: HKHealthStore
    private let appBundleIdentifier: String

    public init(appBundleIdentifier: String) {
        self.store = HKHealthStore()
        self.appBundleIdentifier = appBundleIdentifier
    }

    public var isHealthDataAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    // MARK: - Authorization

    public func requestAuthorization(for capabilities: [HealthCapability]) async throws -> [HealthCapabilityState] {
        guard isHealthDataAvailable else {
            return capabilities.map {
                HealthCapabilityState(capability: $0.rawValue, access: .read, status: .denied)
            }
        }

        let readTypes = Set(capabilities.compactMap(Self.sampleType(for:)))
        let writeTypes = Set(
            capabilities.filter(\.isWritable).compactMap(Self.sampleType(for:))
                .compactMap { $0 as? HKSampleType })

        try await store.requestAuthorization(toShare: writeTypes, read: readTypes)
        return await authorizationStates(for: capabilities)
    }

    /// Per capability, never a single global boolean (§C).
    ///
    /// A deliberate honesty constraint: HealthKit's `authorizationStatus(for:)`
    /// reports **share (write)** authorization only. It cannot tell us whether
    /// reads are permitted — by design, so an app cannot detect that a user
    /// withheld a category. Read capabilities therefore report `.unknowable`
    /// once asked, rather than a comforting `.authorized` we cannot substantiate.
    public func authorizationStates(for capabilities: [HealthCapability]) async -> [HealthCapabilityState] {
        guard isHealthDataAvailable else {
            return capabilities.map {
                HealthCapabilityState(capability: $0.rawValue, access: .read, status: .denied)
            }
        }

        var states: [HealthCapabilityState] = []
        for capability in capabilities {
            guard let type = Self.sampleType(for: capability) else { continue }

            if capability.isWritable, let sampleType = type as? HKSampleType {
                let status: HealthCapabilityState.Status =
                    switch store.authorizationStatus(for: sampleType) {
                    case .sharingAuthorized: .authorized
                    case .sharingDenied: .denied
                    case .notDetermined: .notDetermined
                    @unknown default: .notDetermined
                    }
                states.append(HealthCapabilityState(
                    capability: capability.rawValue, access: .write, status: status))
            }

            // Read status is not knowable; say so rather than guess.
            states.append(HealthCapabilityState(
                capability: capability.rawValue,
                access: .read,
                status: .unknowable))
        }
        return states
    }

    // MARK: - Incremental import

    public func importWorkouts(since cursor: ImportCursor) async throws -> HealthImportBatch {
        guard isHealthDataAvailable else {
            throw HealthImportError.healthDataUnavailable
        }

        let anchor = Self.decodeAnchor(cursor.anchorData)

        let (samples, deletedObjects, newAnchor) = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<([HKSample], [HKDeletedObject], HKQueryAnchor?), Error>) in

            let query = HKAnchoredObjectQuery(
                type: HKObjectType.workoutType(),
                predicate: nil,
                anchor: anchor,
                limit: HKObjectQueryNoLimit
            ) { _, samples, deleted, newAnchor, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: (samples ?? [], deleted ?? [], newAnchor))
                }
            }
            store.execute(query)
        }

        let workouts = samples.compactMap { $0 as? HKWorkout }
        let summaries = workouts.compactMap(summarize)

        var updated = cursor
        updated.anchorData = Self.encodeAnchor(newAnchor)
        updated.lastSuccessfulImport = Date()
        updated.lastAttempt = Date()
        updated.lastErrorDescription = nil

        return HealthImportBatch(
            summaries: summaries,
            deletedProviderIDs: deletedObjects.map { $0.uuid.uuidString },
            updatedCursor: updated,
            rawSampleCount: workouts.count,
            unmappedSampleCount: workouts.count - summaries.count)
    }

    // MARK: - Mapping

    /// Map one `HKWorkout` into a domain summary. Returns `nil` for activity
    /// types Endurance does not track — never a guess (§D).
    private func summarize(_ workout: HKWorkout) -> ExternalWorkoutSummary? {
        guard let sport = HealthActivityMapping.sport(
            forActivityRawValue: workout.workoutActivityType.rawValue) else { return nil }

        let distance = Self.totalDistance(for: workout, sport: sport)
        let energy = workout.statistics(for: HKQuantityType(.activeEnergyBurned))?
            .sumQuantity()?.doubleValue(for: .kilocalorie())
        let heartRate = workout.statistics(for: HKQuantityType(.heartRate))
        let unit = HKUnit.count().unitDivided(by: .minute())

        return ExternalWorkoutSummary(
            provider: .healthKit,
            providerWorkoutID: workout.uuid.uuidString,
            sourceBundleIdentifier: workout.sourceRevision.source.bundleIdentifier,
            sourceName: workout.sourceRevision.source.name,
            deviceName: workout.device?.name,
            sport: sport,
            start: workout.startDate,
            end: workout.endDate,
            durationSeconds: Int(workout.duration),
            distanceMeters: distance,
            activeEnergyKilocalories: energy,
            // Only report metrics HealthKit actually provides. §D forbids
            // fabricating an average from incomplete data.
            averageHeartRate: heartRate?.averageQuantity()?.doubleValue(for: unit),
            maximumHeartRate: heartRate?.maximumQuantity()?.doubleValue(for: unit),
            isIndoor: workout.metadata?[HKMetadataKeyIndoorWorkout] as? Bool,
            isOpenWater: Self.isOpenWater(workout),
            hasRoute: false,
            importedAt: Date(),
            lastObservedAt: Date(),
            // HealthKit does not expose a revision string; field comparison in
            // `ImportReconciler` covers change detection.
            sourceRevision: nil,
            isDeletedAtSource: false)
    }

    private static func totalDistance(for workout: HKWorkout, sport: Sport) -> Double? {
        let type: HKQuantityType? =
            switch sport {
            case .swim: HKQuantityType(.distanceSwimming)
            case .bike: HKQuantityType(.distanceCycling)
            case .run, .recovery: HKQuantityType(.distanceWalkingRunning)
            default: nil
            }
        guard let type else { return nil }
        return workout.statistics(for: type)?.sumQuantity()?.doubleValue(for: .meter())
    }

    private static func isOpenWater(_ workout: HKWorkout) -> Bool? {
        guard workout.workoutActivityType == .swimming else { return nil }
        guard let raw = workout.metadata?[HKMetadataKeySwimmingLocationType] as? NSNumber,
              let location = HKWorkoutSwimmingLocationType(rawValue: raw.intValue) else { return nil }
        return location == .openWater
    }

    // MARK: - Anchor persistence

    private static func encodeAnchor(_ anchor: HKQueryAnchor?) -> Data? {
        guard let anchor else { return nil }
        return try? NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true)
    }

    private static func decodeAnchor(_ data: Data?) -> HKQueryAnchor? {
        guard let data else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
    }

    /// The HealthKit object type backing each capability. Kept exhaustive so a
    /// newly added capability cannot silently request nothing.
    private static func sampleType(for capability: HealthCapability) -> HKObjectType? {
        switch capability {
        case .workouts: return HKObjectType.workoutType()
        case .heartRate: return HKQuantityType(.heartRate)
        case .restingHeartRate: return HKQuantityType(.restingHeartRate)
        case .runningDistance: return HKQuantityType(.distanceWalkingRunning)
        case .cyclingDistance: return HKQuantityType(.distanceCycling)
        case .swimmingDistance: return HKQuantityType(.distanceSwimming)
        case .activeEnergy: return HKQuantityType(.activeEnergyBurned)
        case .cyclingPower: return HKQuantityType(.cyclingPower)
        case .runningPower: return HKQuantityType(.runningPower)
        case .workoutRoute: return HKSeriesType.workoutRoute()
        }
    }
}

#endif

/// Import failures, expressed without leaking framework text to the UI (§P).
public enum HealthImportError: Error, Sendable, Equatable {
    case healthDataUnavailable
    case notAuthorized
    case queryFailed(code: String)

    /// A stable, non-sensitive code for logging. Never carries health values (§Q).
    public var logCode: String {
        switch self {
        case .healthDataUnavailable: return "health.unavailable"
        case .notAuthorized: return "health.not_authorized"
        case .queryFailed(let code): return "health.query_failed.\(code)"
        }
    }
}
