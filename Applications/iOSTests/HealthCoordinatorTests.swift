import XCTest
import SwiftData
import EnduranceDomain
import EnduranceHealth
import EnduranceTrainingPlans
@testable import Endurance

/// §D/§E/§O at the app layer, driven through a deterministic fake importer.
///
/// This is the integration seam that matters: authorization → incremental
/// import → reconciliation → matching → inbox → the athlete's decision. None of
/// it needs HealthKit, a device, or a permission prompt, because the importer is
/// injected as a protocol. Production code never fakes framework success (§T).
@MainActor
final class HealthCoordinatorTests: XCTestCase {

    // MARK: - Fake importer

    /// A test-only importer. Lives in the test target, never in the app.
    private final class FakeImporter: HealthWorkoutImporting, @unchecked Sendable {
        var available = true
        var batches: [HealthImportBatch] = []
        var importCallCount = 0
        var requestedCapabilities: [HealthCapability] = []
        var errorToThrow: HealthImportError?

        var isHealthDataAvailable: Bool { available }

        func requestAuthorization(for capabilities: [HealthCapability]) async throws -> [HealthCapabilityState] {
            requestedCapabilities = capabilities
            return capabilities.map {
                HealthCapabilityState(capability: $0.rawValue, access: .read, status: .unknowable)
            }
        }

        func authorizationStates(for capabilities: [HealthCapability]) async -> [HealthCapabilityState] {
            capabilities.map {
                HealthCapabilityState(capability: $0.rawValue, access: .read, status: .unknowable)
            }
        }

        func importWorkouts(since cursor: ImportCursor) async throws -> HealthImportBatch {
            importCallCount += 1
            if let errorToThrow { throw errorToThrow }
            guard !batches.isEmpty else {
                var advanced = cursor
                advanced.lastSuccessfulImport = Date()
                return HealthImportBatch(summaries: [], updatedCursor: advanced)
            }
            return batches.removeFirst()
        }
    }

    private var container: ModelContainer!
    private var workoutStore: WorkoutStore!
    private var importer: FakeImporter!
    private var coordinator: HealthCoordinator!

    override func setUpWithError() throws {
        let config = ModelConfiguration(schema: EnduranceSchema.current, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: EnduranceSchema.current, configurations: [config])
        workoutStore = WorkoutStore(modelContainer: container)
        try workoutStore.completeOnboarding(
            configuration: ScheduleConfiguration(
                anchor: .startDate(Calendar.current.startOfDay(for: Date())),
                timeZoneIdentifier: TimeZone.current.identifier),
            units: .metric,
            preferences: NotificationPreferences(),
            raceName: nil,
            raceLocation: nil)

        importer = FakeImporter()
        coordinator = HealthCoordinator(
            importer: importer,
            container: container,
            workoutStore: workoutStore,
            appBundleIdentifier: "com.example.endurance")
    }

    override func tearDown() {
        coordinator = nil
        importer = nil
        workoutStore = nil
        container = nil
    }

    // MARK: - Helpers

    private func summary(
        id: String,
        sport: Sport,
        start: Date,
        minutes: Int,
        bundle: String? = "com.apple.health"
    ) -> ExternalWorkoutSummary {
        ExternalWorkoutSummary(
            provider: .healthKit,
            providerWorkoutID: id,
            sourceBundleIdentifier: bundle,
            sourceName: "Apple Watch",
            sport: sport,
            start: start,
            end: start.addingTimeInterval(Double(minutes) * 60),
            durationSeconds: minutes * 60,
            importedAt: Date(),
            lastObservedAt: Date())
    }

    private func batch(_ summaries: [ExternalWorkoutSummary]) -> HealthImportBatch {
        var cursor = ImportCursor(provider: .healthKit)
        cursor.lastSuccessfulImport = Date()
        return HealthImportBatch(summaries: summaries, updatedCursor: cursor)
    }

    private func firstPlanned() throws -> ScheduledWorkout {
        let all = workoutStore.allWorkouts.sorted { $0.plannedStart < $1.plannedStart }
        return try XCTUnwrap(all.first)
    }

    // MARK: - Authorization

    func testConnectRequestsOnlyTheCapabilitiesImportUses() async {
        await coordinator.connect()

        XCTAssertEqual(Set(importer.requestedCapabilities), Set(HealthCapabilityPlan.coreImport))
        XCTAssertFalse(importer.requestedCapabilities.contains(.workoutRoute),
                       "routes must not be requested before route features exist")
        XCTAssertFalse(importer.requestedCapabilities.contains(.restingHeartRate))
    }

    func testUnavailableHealthReportsHonestlyAndDoesNotImport() async {
        importer.available = false
        await coordinator.connect()

        XCTAssertEqual(coordinator.connection, .unavailable)
        XCTAssertEqual(importer.importCallCount, 0)
    }

    /// §C — read authorization is genuinely unknowable, and must be reported so.
    func testReadAuthorizationIsReportedAsUnknowableNotAuthorized() async {
        await coordinator.connect()
        let reads = coordinator.capabilityStates.filter { $0.access == .read }
        XCTAssertFalse(reads.isEmpty)
        XCTAssertTrue(reads.allSatisfy { $0.status == .unknowable },
                      "HealthKit cannot report read access; claiming 'authorized' would be a lie")
    }

    // MARK: - Import and inbox

    func testImportSurfacesAnUnmatchedActivityInTheInbox() async throws {
        // Deliberately far from any planned session, so it stays unmatched.
        let stray = summary(id: "hk-stray", sport: .swim,
                            start: Date().addingTimeInterval(-40 * 24 * 3600), minutes: 40)
        importer.batches = [batch([stray])]

        await coordinator.connect()

        XCTAssertEqual(coordinator.inbox.count, 1)
        XCTAssertEqual(coordinator.inbox.first?.summary.idempotencyKey, "healthKit:hk-stray")
    }

    func testActivityMatchingAPlannedSessionIsSuggestedWithEvidence() async throws {
        let planned = try firstPlanned()
        let activity = summary(id: "hk-match", sport: planned.sport,
                               start: planned.plannedStart.addingTimeInterval(180),
                               minutes: planned.effectivePlannedMinutes)
        importer.batches = [batch([activity])]

        await coordinator.connect()

        let item = try XCTUnwrap(coordinator.inbox.first)
        XCTAssertEqual(item.suggestion?.id, planned.id)
        XCTAssertFalse(item.match.reasons.isEmpty, "a suggestion must carry its evidence")
        XCTAssertTrue(item.match.confidence.isSuggestable)
        XCTAssertFalse(item.match.confidence.mayApplyAutomatically,
                       "a heuristic match must never be applied without confirmation")
    }

    /// §O — Endurance's own exports must not come back as imports.
    func testSelfAuthoredWorkoutIsNeverImported() async {
        let ours = summary(id: "hk-ours", sport: .run, start: Date(), minutes: 45,
                           bundle: "com.example.endurance")
        importer.batches = [batch([ours])]

        await coordinator.connect()

        XCTAssertTrue(coordinator.inbox.isEmpty,
                      "re-importing our own export would double-count it")
    }

    /// §D — the cursor advances, so a second import is incremental.
    func testRepeatedImportDoesNotResurfaceTheSameActivity() async throws {
        let activity = summary(id: "hk-1", sport: .bike,
                               start: Date().addingTimeInterval(-30 * 24 * 3600), minutes: 60)
        importer.batches = [batch([activity]), batch([activity])]

        await coordinator.connect()
        XCTAssertEqual(coordinator.inbox.count, 1)

        await coordinator.runImport()
        XCTAssertEqual(coordinator.inbox.count, 1,
                       "a re-delivered activity must not appear twice")
    }

    // MARK: - Decisions

    func testConfirmingAMatchCompletesThePlannedSessionAndClearsTheInbox() async throws {
        let planned = try firstPlanned()
        let activity = summary(id: "hk-confirm", sport: planned.sport,
                               start: planned.plannedStart.addingTimeInterval(120),
                               minutes: planned.effectivePlannedMinutes)
        importer.batches = [batch([activity])]
        await coordinator.connect()

        let item = try XCTUnwrap(coordinator.inbox.first)
        coordinator.confirm(item, to: planned.id)

        XCTAssertTrue(coordinator.inbox.isEmpty, "a decided activity leaves the inbox")

        let updated = try XCTUnwrap(workoutStore.workout(id: planned.id))
        XCTAssertTrue(updated.status.countsAsDone)
        XCTAssertEqual(updated.completion?.source, .healthKit)
    }

    func testRejectingAMatchRemovesItAndItDoesNotReturnOnReimport() async throws {
        let planned = try firstPlanned()
        let activity = summary(id: "hk-reject", sport: planned.sport,
                               start: planned.plannedStart.addingTimeInterval(120),
                               minutes: planned.effectivePlannedMinutes)
        importer.batches = [batch([activity]), batch([activity])]
        await coordinator.connect()

        coordinator.reject(try XCTUnwrap(coordinator.inbox.first))
        XCTAssertTrue(coordinator.inbox.isEmpty)

        await coordinator.runImport()
        XCTAssertTrue(coordinator.inbox.isEmpty,
                      "a rejected suggestion must not keep coming back")
    }

    func testUndoRestoresARejectedSuggestion() async throws {
        let planned = try firstPlanned()
        let activity = summary(id: "hk-undo", sport: planned.sport,
                               start: planned.plannedStart.addingTimeInterval(120),
                               minutes: planned.effectivePlannedMinutes)
        importer.batches = [batch([activity])]
        await coordinator.connect()

        let item = try XCTUnwrap(coordinator.inbox.first)
        coordinator.reject(item)
        XCTAssertTrue(coordinator.inbox.isEmpty)

        coordinator.undo(item)
        XCTAssertEqual(coordinator.inbox.count, 1, "undo must make the decision reversible")
    }

    func testKeepingAsUnplannedRecordsTrainingWithoutTouchingThePlan() async throws {
        let planned = try firstPlanned()
        let activity = summary(id: "hk-unplanned", sport: planned.sport,
                               start: planned.plannedStart.addingTimeInterval(120),
                               minutes: planned.effectivePlannedMinutes)
        importer.batches = [batch([activity])]
        await coordinator.connect()

        coordinator.keepAsUnplanned(try XCTUnwrap(coordinator.inbox.first))

        XCTAssertTrue(coordinator.inbox.isEmpty)
        let untouched = try XCTUnwrap(workoutStore.workout(id: planned.id))
        XCTAssertFalse(untouched.status.countsAsDone,
                       "keeping an activity as unplanned must not complete a planned session")
    }

    // MARK: - Failure and disconnect

    func testImportFailureIsRecordedWithoutLosingTrainingData() async throws {
        importer.errorToThrow = .queryFailed(code: "test")
        await coordinator.connect()

        XCTAssertNotNil(coordinator.lastErrorCode)
        XCTAssertFalse(workoutStore.allWorkouts.isEmpty,
                       "an import failure must not disturb the plan")
    }

    /// §F/§Q — disconnecting clears integration records but keeps history.
    func testDisconnectClearsIntegrationRecordsButKeepsTrainingHistory() async throws {
        let planned = try firstPlanned()
        let activity = summary(id: "hk-keep", sport: planned.sport,
                               start: planned.plannedStart.addingTimeInterval(120),
                               minutes: planned.effectivePlannedMinutes)
        importer.batches = [batch([activity])]
        await coordinator.connect()
        coordinator.confirm(try XCTUnwrap(coordinator.inbox.first), to: planned.id)

        coordinator.disconnect()

        XCTAssertFalse(coordinator.isImportEnabled)
        XCTAssertTrue(coordinator.inbox.isEmpty)

        // The completion stays — that is the athlete's training record.
        let stillDone = try XCTUnwrap(workoutStore.workout(id: planned.id))
        XCTAssertTrue(stillDone.status.countsAsDone,
                      "disconnecting Health must never erase training history")
        XCTAssertEqual(workoutStore.allWorkouts.count, 382)
    }
}
