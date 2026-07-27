import Testing
import Foundation
@testable import EnduranceHealth
@testable import EnduranceDomain

/// §O — duplicate prevention, which the brief calls release-critical.
///
/// There is one user-visible failure this whole file exists to prevent: two
/// completed workouts appearing for one physical session merely because it was
/// observed through two Apple frameworks. Each test below is one of the
/// pathways §O enumerates.
@Suite("Duplicate prevention")
struct DuplicatePreventionTests {

    private let appBundleID = "com.example.endurance"
    private let reconciler = ImportReconciler(appBundleIdentifier: "com.example.endurance")

    private func summary(
        id: String = "hk-1",
        sport: Sport = .run,
        start: Date = Date(timeIntervalSince1970: 1_770_000_000),
        minutes: Int = 45,
        distance: Double? = 8000,
        bundle: String? = "com.apple.health",
        revision: String? = nil,
        deleted: Bool = false
    ) -> ExternalWorkoutSummary {
        ExternalWorkoutSummary(
            provider: .healthKit,
            providerWorkoutID: id,
            sourceBundleIdentifier: bundle,
            sport: sport,
            start: start,
            end: start.addingTimeInterval(Double(minutes) * 60),
            durationSeconds: minutes * 60,
            distanceMeters: distance,
            importedAt: Date(),
            lastObservedAt: Date(),
            sourceRevision: revision,
            isDeletedAtSource: deleted)
    }

    private func batch(_ summaries: [ExternalWorkoutSummary], deleted: [String] = []) -> HealthImportBatch {
        HealthImportBatch(
            summaries: summaries,
            deletedProviderIDs: deleted,
            updatedCursor: ImportCursor(provider: .healthKit))
    }

    // MARK: - Pathway: app relaunch repeats an anchored query result

    @Test("A re-delivered, unchanged activity is not surfaced again")
    func relaunchRedeliveryIsNotNew() {
        let existing = summary(revision: "rev-1")
        let known = ImportReconciler.KnownState(summaries: [existing.idempotencyKey: existing])

        let outcome = reconciler.reconcile(batch([existing]), known: known)

        #expect(outcome.newSummaries.isEmpty, "a relaunch must not re-surface known activities")
        #expect(outcome.unchangedKeys == [existing.idempotencyKey])
        #expect(!outcome.hasChanges)
    }

    @Test("A genuinely edited activity is reported as an update, not a new import")
    func editedActivityIsAnUpdate() {
        let original = summary(revision: "rev-1")
        let edited = summary(minutes: 52, revision: "rev-2")
        let known = ImportReconciler.KnownState(summaries: [original.idempotencyKey: original])

        let outcome = reconciler.reconcile(batch([edited]), known: known)

        #expect(outcome.newSummaries.isEmpty)
        #expect(outcome.updatedSummaries.count == 1)
        #expect(outcome.hasChanges)
    }

    @Test("Without a revision marker, unchanged fields still count as unchanged")
    func fieldComparisonFallback() {
        let existing = summary()
        let known = ImportReconciler.KnownState(summaries: [existing.idempotencyKey: existing])
        let outcome = reconciler.reconcile(batch([existing]), known: known)
        #expect(outcome.unchangedKeys.count == 1)
    }

    // MARK: - Pathway: Endurance's own export returns as an import

    @Test("A workout Endurance itself wrote is never re-imported")
    func selfAuthoredIsSkipped() {
        let ours = summary(bundle: appBundleID)
        let outcome = reconciler.reconcile(batch([ours]), known: .init())

        #expect(outcome.newSummaries.isEmpty,
                "re-importing our own export would double-count every exported session")
        #expect(outcome.skippedSelfAuthored == [ours.idempotencyKey])
    }

    // MARK: - Pathway: watch completion already recorded, then HealthKit sees it

    @Test("An activity already attached to an execution is not offered for review")
    func alreadyExecutedIsNotSurfaced() {
        let activity = summary()
        let known = ImportReconciler.KnownState(executionKeys: [activity.idempotencyKey])

        let outcome = reconciler.reconcile(batch([activity]), known: known)

        #expect(outcome.newSummaries.isEmpty)
        #expect(outcome.unchangedKeys == [activity.idempotencyKey])
    }

    // MARK: - Noise filtering

    @Test("A stray thirty-second activity is not surfaced")
    func tooShortIsSkipped() {
        let stray = summary(id: "hk-stray", minutes: 0, distance: nil)
        let outcome = reconciler.reconcile(batch([stray]), known: .init())
        #expect(outcome.newSummaries.isEmpty)
        #expect(outcome.skippedTooShort == [stray.idempotencyKey])
    }

    @Test("A real session is surfaced exactly once")
    func newActivityIsSurfaced() {
        let activity = summary()
        let outcome = reconciler.reconcile(batch([activity]), known: .init())
        #expect(outcome.newSummaries.map(\.idempotencyKey) == [activity.idempotencyKey])
        #expect(outcome.hasChanges)
    }

    // MARK: - Deletions

    @Test("Deletions are reported only for activities we knew about")
    func deletionsAreScopedToKnownActivities() {
        let known1 = summary(id: "hk-1")
        let state = ImportReconciler.KnownState(summaries: [known1.idempotencyKey: known1])

        let outcome = reconciler.reconcile(
            batch([], deleted: ["hk-1", "hk-never-seen"]),
            known: state)

        #expect(outcome.deletedKeys == ["healthKit:hk-1"])
    }

    // MARK: - Idempotency of the whole batch

    @Test("Reconciling the same batch twice yields no second import")
    func reconciliationIsIdempotent() {
        let activity = summary()
        let first = reconciler.reconcile(batch([activity]), known: .init())
        #expect(first.newSummaries.count == 1)

        // Simulate having persisted the first outcome.
        let known = ImportReconciler.KnownState(summaries: [activity.idempotencyKey: activity])
        let second = reconciler.reconcile(batch([activity]), known: known)
        #expect(second.newSummaries.isEmpty)
    }
}

/// §O — execution-level de-duplication, where one physical session is observed
/// by more than one framework.
@Suite("Execution merging")
struct ExecutionMergerTests {

    private let merger = ExecutionMerger()
    private let base = Date(timeIntervalSince1970: 1_770_000_000)

    private func execution(
        id: UUID = UUID(),
        session: UUID? = nil,
        source: CompletionSource = .appleWatch,
        start: Date? = nil,
        minutes: Int = 60,
        keys: Set<String> = []
    ) -> WorkoutExecution {
        WorkoutExecution(
            id: id,
            scheduledWorkoutID: session,
            source: source,
            start: start ?? base,
            durationSeconds: minutes * 60,
            externalKeys: keys)
    }

    // MARK: - Pathway: user taps save twice / watch retries a transfer

    @Test("The same execution delivered twice is ignored, not duplicated")
    func repeatedDeliveryIsIgnored() {
        let existing = execution()
        let resolution = merger.resolve(incoming: existing, externalKey: nil, against: [existing])
        #expect(resolution == .ignore(existingID: existing.id))
    }

    @Test("A retried transfer carrying a new external key attaches it")
    func retryAttachesNewKey() {
        let existing = execution()
        let resolution = merger.resolve(
            incoming: existing, externalKey: "healthKit:hk-9", against: [existing])
        #expect(resolution == .attach(existingID: existing.id, externalKey: "healthKit:hk-9"))
    }

    // MARK: - Pathway: watch saves to HealthKit AND syncs the completion

    @Test("A HealthKit import of an already-synced watch workout attaches, never inserts")
    func healthImportOfSyncedWatchWorkout() {
        let session = UUID()
        let fromWatch = execution(session: session, source: .appleWatch, keys: ["healthKit:hk-77"])

        // HealthKit later reports the same workout as a fresh execution.
        let fromHealth = execution(session: session, source: .healthKit, start: base.addingTimeInterval(30))

        let resolution = merger.resolve(
            incoming: fromHealth, externalKey: "healthKit:hk-77", against: [fromWatch])

        #expect(resolution == .ignore(existingID: fromWatch.id),
                "one ride must not become two completed workouts")
    }

    // MARK: - Pathway: manual completion, then a matching HealthKit import

    @Test("A HealthKit import coinciding with a manual completion attaches to it")
    func manualThenImportAttaches() {
        let session = UUID()
        let manual = execution(session: session, source: .manual, start: base, minutes: 45)
        let imported = execution(session: session, source: .healthKit,
                                 start: base.addingTimeInterval(4 * 60), minutes: 46)

        let resolution = merger.resolve(
            incoming: imported, externalKey: "healthKit:hk-12", against: [manual])

        #expect(resolution == .attach(existingID: manual.id, externalKey: "healthKit:hk-12"),
                "an import must not silently replace or duplicate a manual completion")
    }

    // MARK: - Genuine separates

    @Test("A second, genuinely separate session later the same day is inserted")
    func separateSessionIsInserted() {
        let session = UUID()
        let morning = execution(session: session, start: base, minutes: 45)
        let evening = execution(session: nil, start: base.addingTimeInterval(8 * 3600), minutes: 45)

        let resolution = merger.resolve(incoming: evening, externalKey: nil, against: [morning])

        guard case .insert = resolution else {
            Issue.record("a genuinely separate session must be recorded, got \(resolution)")
            return
        }
    }

    @Test("Unplanned training with a distinct start and duration is its own execution")
    func unplannedDistinctIsInserted() {
        let existing = execution(session: nil, start: base, minutes: 30)
        let other = execution(session: nil, start: base.addingTimeInterval(60), minutes: 90)

        let resolution = merger.resolve(incoming: other, externalKey: nil, against: [existing])
        guard case .insert = resolution else {
            Issue.record("durations 60 minutes apart are not the same session, got \(resolution)")
            return
        }
    }

    @Test("An empty history always inserts")
    func firstExecutionInserts() {
        let resolution = merger.resolve(incoming: execution(), externalKey: nil, against: [])
        guard case .insert = resolution else {
            Issue.record("expected insert, got \(resolution)")
            return
        }
    }
}

/// §D — the activity mapping is a closed, explicit table. An unknown type must
/// be skipped, never guessed at.
@Suite("Health activity mapping")
struct HealthActivityMappingTests {

    @Test("Core triathlon activities map to the right sports")
    func coreSportsMap() {
        #expect(HealthActivityMapping.sport(forActivityRawValue: 46) == .swim)
        #expect(HealthActivityMapping.sport(forActivityRawValue: 13) == .bike)
        #expect(HealthActivityMapping.sport(forActivityRawValue: 37) == .run)
        #expect(HealthActivityMapping.sport(forActivityRawValue: 50) == .strength)
    }

    @Test("An unmapped activity type is skipped rather than guessed")
    func unknownActivityIsSkipped() {
        // 3000 is not a real HKWorkoutActivityType constant.
        #expect(HealthActivityMapping.sport(forActivityRawValue: 3000) == nil)
    }

    @Test("Multisport containers are identified")
    func multisportIsIdentified() {
        #expect(HealthActivityMapping.isMultisport(82))
        #expect(HealthActivityMapping.isMultisport(76))
        #expect(!HealthActivityMapping.isMultisport(37))
    }

    @Test("Export refuses sports with no honest HealthKit representation")
    func exportRefusesMultisport() {
        #expect(HealthActivityMapping.activityRawValue(for: .run) == 37)
        #expect(HealthActivityMapping.activityRawValue(for: .swim) == 46)
        #expect(HealthActivityMapping.activityRawValue(for: .brick) == nil,
                "a brick is multisport; filing it as one activity would be wrong")
        #expect(HealthActivityMapping.activityRawValue(for: .race) == nil)
    }

    @Test("Round-tripping a mapped sport preserves it")
    func roundTripIsStable() {
        for sport in [Sport.swim, .bike, .run, .strength] {
            let raw = try? #require(HealthActivityMapping.activityRawValue(for: sport))
            if let raw {
                #expect(HealthActivityMapping.sport(forActivityRawValue: raw) == sport)
            }
        }
    }

    @Test("Only capabilities a visible feature uses are in the core request")
    func capabilityPlanIsMinimal() {
        let core = Set(HealthCapabilityPlan.coreImport)
        #expect(core.contains(.workouts))
        #expect(core.contains(.heartRate))
        #expect(!core.contains(.workoutRoute), "routes are requested only when route features ship")
        #expect(!core.contains(.restingHeartRate), "requested only once something displays it")
    }

    @Test("Per-sport capability requests stay scoped to that sport's distance")
    func perSportCapabilities() {
        let swim = Set(HealthCapabilityPlan.readCapabilities(for: .swim))
        #expect(swim.contains(.swimmingDistance))
        #expect(!swim.contains(.cyclingDistance))

        let bike = Set(HealthCapabilityPlan.readCapabilities(for: .bike))
        #expect(bike.contains(.cyclingDistance))
        #expect(!bike.contains(.swimmingDistance))
    }

    @Test("Only workouts and energy are ever written")
    func writeSetIsNarrow() {
        #expect(Set(HealthCapabilityPlan.export) == [.workouts, .activeEnergy])
        #expect(HealthCapability.workouts.isWritable)
        #expect(!HealthCapability.heartRate.isWritable, "Endurance never writes heart rate")
        #expect(!HealthCapability.restingHeartRate.isWritable)
    }
}
