import XCTest
import SwiftData
import EnduranceDomain
import EnduranceHealth
import EnduranceTrainingPlans
@testable import Endurance

/// §3/§5/§9/§10 — the export workflow at the app layer.
///
/// Driven through a fake exporter, so failure paths that are impossible to
/// provoke on a device — a save that succeeds while persistence fails, a crash
/// mid-save — are exercised deterministically. Production code never fakes
/// HealthKit success (§10).
@MainActor
final class HealthExportTests: XCTestCase {

    // MARK: - Fake exporter

    private final class FakeExporter: HealthExporting, @unchecked Sendable {
        var available = true
        var writeStatus: HealthCapabilityState.Status = .authorized
        var saveError: HealthExportError?
        var deleteError: HealthExportError?
        var savedPayloads: [HealthWorkoutExportPayload] = []
        var deletedIDs: [String] = []
        var nextProviderID = "hk-generated-1"
        /// Simulates a workout HealthKit accepted, discoverable by metadata.
        var orphanLookup: [UUID: String] = [:]

        var isHealthDataAvailable: Bool { available }

        func requestWriteAuthorization() async throws -> [HealthCapabilityState] {
            writeAuthorizationStates()
        }

        func writeAuthorizationStates() -> [HealthCapabilityState] {
            HealthCapabilityPlan.export.map {
                HealthCapabilityState(capability: $0.rawValue, access: .write, status: writeStatus)
            }
        }

        func save(_ payload: HealthWorkoutExportPayload) async throws -> String {
            if let saveError { throw saveError }
            savedPayloads.append(payload)
            return nextProviderID
        }

        func replace(providerWorkoutID: String, with payload: HealthWorkoutExportPayload) async throws -> String {
            let id = try await save(payload)
            try await delete(providerWorkoutID: providerWorkoutID)
            return id
        }

        func delete(providerWorkoutID: String) async throws {
            if let deleteError { throw deleteError }
            deletedIDs.append(providerWorkoutID)
        }

        func findExportedWorkout(executionID: UUID) async throws -> String? {
            orphanLookup[executionID]
        }
    }

    private var container: ModelContainer!
    private var exporter: FakeExporter!
    private var coordinator: HealthExportCoordinator!

    override func setUpWithError() throws {
        let config = ModelConfiguration(schema: EnduranceSchema.current, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: EnduranceSchema.current, configurations: [config])
        exporter = FakeExporter()
        coordinator = HealthExportCoordinator(exporter: exporter, container: container)
        coordinator.refreshAuthorization()
        coordinator.isAutoExportEnabled = true
    }

    override func tearDown() {
        coordinator = nil
        exporter = nil
        container = nil
    }

    // MARK: - Helpers

    private func execution(
        source: CompletionSource = .manual,
        minutes: Int = 45,
        distance: Double? = 9000
    ) -> WorkoutExecution {
        let e = WorkoutExecution(
            scheduledWorkoutID: UUID(),
            source: source,
            start: Date(timeIntervalSince1970: 1_770_000_000),
            durationSeconds: minutes * 60,
            distanceMeters: distance)
        let context = ModelContext(container)
        if let row = try? SDWorkoutExecution(domain: e) {
            context.insert(row)
            try? context.save()
        }
        return e
    }

    // MARK: - Successful export

    func testEligibleWorkoutExportsAndPersistsProviderReference() async throws {
        let e = execution()

        let result = await coordinator.export(execution: e, sport: .run)

        XCTAssertEqual(result, .alreadyExported(providerWorkoutID: "hk-generated-1"))
        XCTAssertEqual(exporter.savedPayloads.count, 1)

        let record = try XCTUnwrap(coordinator.record(for: e.id))
        XCTAssertEqual(record.status, .saved)
        XCTAssertEqual(record.providerWorkoutID, "hk-generated-1")
        XCTAssertTrue(record.isEnduranceOwned)
        XCTAssertNotNil(record.exportedAt)
    }

    func testExportedPayloadCarriesIdentityAndNoFabricatedMetrics() async throws {
        let e = execution(distance: nil)
        await coordinator.export(execution: e, sport: .run)

        let payload = try XCTUnwrap(exporter.savedPayloads.first)
        XCTAssertEqual(payload.executionID, e.id)
        XCTAssertEqual(payload.idempotencyKey, HealthExportRecord.idempotencyKey(for: e.id))
        XCTAssertNil(payload.distanceMeters, "a missing distance must not be invented")
        XCTAssertNil(payload.activeEnergyKilocalories, "calories are never invented")
        XCTAssertTrue(payload.wasUserEntered)
    }

    // MARK: - Idempotency (§3)

    func testSecondExportOfTheSameExecutionDoesNotSaveAgain() async throws {
        let e = execution()
        await coordinator.export(execution: e, sport: .run)
        let second = await coordinator.export(execution: e, sport: .run)

        XCTAssertEqual(exporter.savedPayloads.count, 1, "a repeat export must not write twice")
        XCTAssertEqual(second, .alreadyExported(providerWorkoutID: "hk-generated-1"))
    }

    func testConcurrentExportsOfTheSameExecutionSaveOnce() async throws {
        let e = execution()

        // Two rapid taps, or a UI action racing an App Intent. The coordinator
        // is @MainActor (and so Sendable); the test case is not, hence the
        // local capture.
        let target = coordinator!
        let first = Task { @MainActor in await target.export(execution: e, sport: .run) }
        let second = Task { @MainActor in await target.export(execution: e, sport: .run) }
        _ = await first.value
        _ = await second.value

        XCTAssertEqual(exporter.savedPayloads.count, 1,
                       "concurrent attempts must collapse to a single save")
    }

    // MARK: - Refusals

    func testImportedWorkoutIsNeverExported() async {
        let e = execution(source: .healthKit)
        let result = await coordinator.export(execution: e, sport: .run)

        XCTAssertEqual(result, .importedFromHealthKit)
        XCTAssertTrue(exporter.savedPayloads.isEmpty)
    }

    func testWatchRecordedExecutionIsNeverExported() async {
        let e = execution(source: .appleWatch)
        let result = await coordinator.export(execution: e, sport: .run)

        guard case .externallyOwned = result else {
            return XCTFail("expected externallyOwned, got \(result)")
        }
        XCTAssertTrue(exporter.savedPayloads.isEmpty)
    }

    func testBrickIsRefusedRatherThanFiledAsOneActivity() async {
        let e = execution()
        let result = await coordinator.export(execution: e, sport: .brick)

        XCTAssertEqual(result, .unsupportedMultisport(.brick))
        XCTAssertTrue(exporter.savedPayloads.isEmpty)
    }

    func testAutoExportDisabledDoesNotSave() async {
        coordinator.isAutoExportEnabled = false
        let e = execution()
        await coordinator.exportIfAutomatic(execution: e, sport: .run)
        XCTAssertTrue(exporter.savedPayloads.isEmpty)
    }

    func testPermissionDeniedReportsPermissionRequired() async {
        exporter.writeStatus = .denied
        coordinator.refreshAuthorization()

        let result = await coordinator.export(execution: execution(), sport: .run)
        XCTAssertEqual(result, .permissionRequired)
        XCTAssertTrue(exporter.savedPayloads.isEmpty)
    }

    // MARK: - Failure and retry (§5, §8)

    func testSaveFailureIsRecordedAndRetryable() async throws {
        exporter.saveError = .saveFailed
        let e = execution()

        let result = await coordinator.export(execution: e, sport: .run)
        XCTAssertEqual(result, .failedRetryable(category: .saveFailed))
        XCTAssertTrue(result.isRetryable)

        // The local execution is untouched — history never depends on HealthKit.
        let context = ModelContext(container)
        let rows = try context.fetch(FetchDescriptor<SDWorkoutExecution>())
        XCTAssertEqual(rows.count, 1, "a failed export must not remove the local execution")
    }

    func testRetryAfterFailureSucceeds() async throws {
        exporter.saveError = .saveFailed
        let e = execution()
        await coordinator.export(execution: e, sport: .run)

        exporter.saveError = nil
        let result = await coordinator.export(execution: e, sport: .run)

        XCTAssertEqual(result, .alreadyExported(providerWorkoutID: "hk-generated-1"))
        XCTAssertEqual(exporter.savedPayloads.count, 1)
    }

    // MARK: - Orphan recovery (§9)

    func testAnOrphanedExportIsReconnectedThroughMetadata() async throws {
        let e = execution()

        // Simulate: HealthKit accepted the save, we never stored the link.
        var pending = HealthExportRecord(
            executionID: e.id,
            idempotencyKey: HealthExportRecord.idempotencyKey(for: e.id),
            status: .pending)
        pending.providerWorkoutID = nil
        let context = ModelContext(container)
        context.insert(try SDHealthExportRecord(domain: pending))
        try context.save()

        XCTAssertTrue(try XCTUnwrap(coordinator.record(for: e.id)).isPotentialOrphan)

        exporter.orphanLookup[e.id] = "hk-orphan-77"
        await coordinator.recoverOrphanedExports()

        let recovered = try XCTUnwrap(coordinator.record(for: e.id))
        XCTAssertEqual(recovered.status, .saved)
        XCTAssertEqual(recovered.providerWorkoutID, "hk-orphan-77")
        XCTAssertFalse(recovered.isPotentialOrphan,
                       "a successful HealthKit save must never stay invisible")
    }

    func testRecoveryLeavesGenuineFailuresAlone() async throws {
        let e = execution()
        var pending = HealthExportRecord(
            executionID: e.id,
            idempotencyKey: HealthExportRecord.idempotencyKey(for: e.id),
            status: .pending)
        pending.providerWorkoutID = nil
        let context = ModelContext(container)
        context.insert(try SDHealthExportRecord(domain: pending))
        try context.save()

        // Nothing in HealthKit matches — the save really did fail.
        await coordinator.recoverOrphanedExports()

        let unchanged = try XCTUnwrap(coordinator.record(for: e.id))
        XCTAssertEqual(unchanged.status, .pending)
        XCTAssertNil(unchanged.providerWorkoutID)
    }

    // MARK: - Deletion and ownership (§7)

    func testEnduranceOwnedWorkoutCanBeDeleted() async throws {
        let e = execution()
        await coordinator.export(execution: e, sport: .run)

        let result = await coordinator.deleteExportedWorkout(executionID: e.id)
        guard case .success = result else {
            return XCTFail("expected deletion to succeed, got \(result)")
        }
        XCTAssertEqual(exporter.deletedIDs, ["hk-generated-1"])
    }

    func testForeignWorkoutIsNeverDeleted() async throws {
        let e = execution()
        var foreign = HealthExportRecord(
            executionID: e.id,
            idempotencyKey: "k",
            status: .saved,
            providerWorkoutID: "hk-someone-else",
            isEnduranceOwned: false)
        foreign.updatedAt = Date()
        let context = ModelContext(container)
        context.insert(try SDHealthExportRecord(domain: foreign))
        try context.save()

        let result = await coordinator.deleteExportedWorkout(executionID: e.id)
        guard case .failure(.notEnduranceOwned) = result else {
            return XCTFail("expected notEnduranceOwned, got \(result)")
        }
        XCTAssertTrue(exporter.deletedIDs.isEmpty,
                      "Endurance must never delete another app's workout")
    }

    func testDeletingWithoutAnExportRecordIsRefused() async {
        let result = await coordinator.deleteExportedWorkout(executionID: UUID())
        guard case .failure(.noProviderReference) = result else {
            return XCTFail("expected noProviderReference, got \(result)")
        }
        XCTAssertTrue(exporter.deletedIDs.isEmpty)
    }

    func testRemovingLocalRecordsDoesNotTouchHealth() async throws {
        let e = execution()
        await coordinator.export(execution: e, sport: .run)

        coordinator.removeLocalConnectionRecords()

        XCTAssertTrue(exporter.deletedIDs.isEmpty,
                      "removing local records must not delete anything from Health")
        XCTAssertNil(coordinator.record(for: e.id))
    }

    // MARK: - Round trip (§3)

    /// The full loop §3 asks for: export, then have the anchored importer return
    /// the very workout we wrote, and confirm it does not become a second
    /// completed session.
    func testExportedWorkoutReturningThroughImportDoesNotDuplicate() async throws {
        let e = execution()
        await coordinator.export(execution: e, sport: .run)

        let providerID = try XCTUnwrap(coordinator.record(for: e.id)?.providerWorkoutID)

        // HealthKit now reports that workout back to us, attributed to Endurance.
        let returning = ExternalWorkoutSummary(
            provider: .healthKit,
            providerWorkoutID: providerID,
            sourceBundleIdentifier: "com.example.endurance",
            sport: .run,
            start: e.start,
            end: e.start.addingTimeInterval(TimeInterval(e.durationSeconds)),
            durationSeconds: e.durationSeconds,
            distanceMeters: e.distanceMeters,
            importedAt: Date(),
            lastObservedAt: Date())

        let reconciler = ImportReconciler(appBundleIdentifier: "com.example.endurance")
        let outcome = reconciler.reconcile(
            HealthImportBatch(summaries: [returning],
                              updatedCursor: ImportCursor(provider: .healthKit)),
            known: .init())

        XCTAssertTrue(outcome.newSummaries.isEmpty,
                      "our own export must never come back as a new activity")
        XCTAssertEqual(outcome.skippedSelfAuthored, [returning.idempotencyKey])

        // And the merger agrees it is the same execution, not a second one.
        let merger = ExecutionMerger()
        var linked = e
        linked.externalKeys.insert(returning.idempotencyKey)
        let resolution = merger.resolve(
            incoming: e, externalKey: returning.idempotencyKey, against: [linked])
        XCTAssertEqual(resolution, .ignore(existingID: e.id))
    }
}
