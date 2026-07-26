import XCTest
import SwiftData
import EnduranceDomain
import EnduranceTrainingPlans
@testable import Endurance

/// §A / §N — Release 1 data must survive the move to schema v2 without loss and
/// without reinstalling.
///
/// These build a **real Release 1 store on disk** using only the V1 entity set,
/// then reopen that same file through the V2 container and migration plan. A
/// test that merely constructs a V2 store and checks it works would prove
/// nothing about migration; the point is the file written by the old schema.
@MainActor
final class MigrationTests: XCTestCase {

    private var storeURL: URL!

    override func setUpWithError() throws {
        let directory = URL.temporaryDirectory
            .appending(path: "endurance-migration-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        storeURL = directory.appending(path: "default.store")
    }

    override func tearDownWithError() throws {
        let directory = storeURL.deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }

    // MARK: - Fixture construction

    /// A Release 1 store containing exactly what §A asks for: a fresh plan, a
    /// completed workout, a rescheduled workout, settings, and history.
    private struct Fixture {
        var scheduledCount: Int
        var completedID: UUID
        var rescheduledID: UUID
        var rescheduledDate: Date
        var completionNote: String
        var units: MeasurementSystem
        var preferredLongBikeWeekday: Int
    }

    @discardableResult
    private func writeReleaseOneStore() throws -> Fixture {
        // V1 schema only — this is what a Release 1 build would have created.
        let v1Schema = Schema(versionedSchema: EnduranceSchemaV1.self)
        let config = ModelConfiguration(schema: v1Schema, url: storeURL)
        let container = try ModelContainer(for: v1Schema, configurations: [config])
        let context = ModelContext(container)

        let plan = try BundledPlans.load36Week()
        var scheduleConfig = ScheduleConfiguration(
            anchor: .startDate(Calendar.current.startOfDay(for: Date())),
            timeZoneIdentifier: TimeZone.current.identifier)
        scheduleConfig.preferredLongBikeWeekday = 1 // a non-default choice
        scheduleConfig.preferredLongRunWeekday = 7
        scheduleConfig.preferredRestWeekday = 6

        let schedule = try ScheduleEngine().generateSchedule(plan: plan, config: scheduleConfig)
        XCTAssertFalse(schedule.isEmpty)

        // Completed workout, with a note so we can prove history survived.
        var completed = schedule[0]
        let note = "Felt strong, held zone 2 throughout."
        completed.status = .completed
        completed.completion = WorkoutCompletion(
            completedAt: Date(),
            actualDurationMinutes: 47,
            perceivedExertion: 6,
            notes: note,
            source: .manual)

        // Rescheduled workout, with its modification history.
        var rescheduled = schedule[1]
        let movedTo = Calendar.current.date(byAdding: .day, value: 3, to: rescheduled.scheduledDate)!
        let originalDate = rescheduled.scheduledDate
        rescheduled.scheduledDate = movedTo
        rescheduled.status = .rescheduled
        rescheduled.modifications.append(
            PlanModification(type: .reschedule, createdAt: Date(),
                             oldDate: originalDate, newDate: movedTo))

        var all = schedule
        all[0] = completed
        all[1] = rescheduled
        for workout in all {
            context.insert(try SDScheduledWorkout(domain: workout))
        }

        let settings = SDAppSettings()
        settings.onboarded = true
        settings.planID = plan.id
        settings.units = .imperial
        settings.configuration = scheduleConfig
        settings.preferences = NotificationPreferences(enabledCategories: [.workout, .weeklyReview])
        settings.raceName = "Test Iron Distance"
        context.insert(settings)

        try context.save()

        return Fixture(
            scheduledCount: all.count,
            completedID: completed.id,
            rescheduledID: rescheduled.id,
            rescheduledDate: movedTo,
            completionNote: note,
            units: .imperial,
            preferredLongBikeWeekday: 1)
    }

    /// Reopen the same file under the current schema + migration plan.
    private func openMigratedContainer() throws -> ModelContainer {
        let config = ModelConfiguration(schema: EnduranceSchema.current, url: storeURL)
        return try ModelContainer(
            for: EnduranceSchema.current,
            migrationPlan: EnduranceSchema.migrationPlan,
            configurations: [config])
    }

    // MARK: - Tests

    func testReleaseOneStoreMigratesWithoutLoss() throws {
        let fixture = try writeReleaseOneStore()

        let migrated = try openMigratedContainer()
        let context = ModelContext(migrated)

        let records = try context.fetch(FetchDescriptor<SDScheduledWorkout>())
        XCTAssertEqual(records.count, fixture.scheduledCount,
                       "Every scheduled workout must survive migration.")

        // Completion history preserved, including the athlete's own note.
        let completed = try XCTUnwrap(records.first { $0.id == fixture.completedID })
        let completedDomain = try completed.toDomain()
        XCTAssertEqual(completedDomain.status, .completed)
        XCTAssertEqual(completedDomain.completion?.notes, fixture.completionNote)
        XCTAssertEqual(completedDomain.completion?.actualDurationMinutes, 47)
        XCTAssertEqual(completedDomain.completion?.perceivedExertion, 6)

        // Reschedule preserved, including its modification audit trail.
        let rescheduled = try XCTUnwrap(records.first { $0.id == fixture.rescheduledID })
        let rescheduledDomain = try rescheduled.toDomain()
        XCTAssertEqual(rescheduledDomain.status, .rescheduled)
        XCTAssertEqual(
            Calendar.current.startOfDay(for: rescheduledDomain.scheduledDate),
            Calendar.current.startOfDay(for: fixture.rescheduledDate))
        XCTAssertEqual(rescheduledDomain.modifications.count, 1)
        XCTAssertEqual(rescheduledDomain.modifications.first?.type, .reschedule)
    }

    func testSettingsAndPreferencesSurviveMigration() throws {
        let fixture = try writeReleaseOneStore()

        let context = ModelContext(try openMigratedContainer())
        let settings = try XCTUnwrap(try context.fetch(FetchDescriptor<SDAppSettings>()).first)

        XCTAssertTrue(settings.onboarded)
        XCTAssertEqual(settings.units, fixture.units)
        XCTAssertEqual(settings.raceName, "Test Iron Distance")
        XCTAssertEqual(settings.preferences.enabledCategories, [.workout, .weeklyReview])
        XCTAssertEqual(settings.configuration?.preferredLongBikeWeekday,
                       fixture.preferredLongBikeWeekday,
                       "Preferred training days must not be lost.")
    }

    /// §A: deterministic identifiers must not change. If they did, completion
    /// history would detach from the plan even though both survived.
    func testDeterministicIdentifiersAreUnchangedByMigration() throws {
        _ = try writeReleaseOneStore()

        let before = try Set(ModelContext(try ModelContainer(
            for: Schema(versionedSchema: EnduranceSchemaV1.self),
            configurations: [ModelConfiguration(
                schema: Schema(versionedSchema: EnduranceSchemaV1.self), url: storeURL)]))
            .fetch(FetchDescriptor<SDScheduledWorkout>())
            .map(\.id))

        let after = try Set(ModelContext(try openMigratedContainer())
            .fetch(FetchDescriptor<SDScheduledWorkout>())
            .map(\.id))

        XCTAssertEqual(before, after, "Scheduled workout ids must be stable across migration.")
        XCTAssertFalse(after.isEmpty)
    }

    /// Migration must be idempotent — opening an already-migrated store again
    /// must not duplicate or drop anything.
    func testRepeatedMigrationIsIdempotent() throws {
        let fixture = try writeReleaseOneStore()

        for pass in 1...3 {
            let context = ModelContext(try openMigratedContainer())
            let count = try context.fetchCount(FetchDescriptor<SDScheduledWorkout>())
            XCTAssertEqual(count, fixture.scheduledCount, "Pass \(pass) changed the row count.")

            let settingsCount = try context.fetchCount(FetchDescriptor<SDAppSettings>())
            XCTAssertEqual(settingsCount, 1, "Pass \(pass) duplicated settings.")
        }
    }

    /// The new Release 2 entities must exist and be usable after migration —
    /// and must start empty rather than inventing records.
    func testReleaseTwoEntitiesAreAvailableAndEmptyAfterMigration() throws {
        _ = try writeReleaseOneStore()
        let context = ModelContext(try openMigratedContainer())

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SDExternalWorkoutRecord>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SDWorkoutExecution>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SDWorkoutMatchDecision>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SDHealthImportCursor>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SDActiveWorkoutRecovery>()), 0)

        // And they accept writes on the migrated store.
        let summary = ExternalWorkoutSummary(
            provider: .healthKit, providerWorkoutID: "fixture-1",
            sport: .run, start: Date(), end: Date().addingTimeInterval(1800),
            durationSeconds: 1800, importedAt: Date(), lastObservedAt: Date())
        context.insert(try SDExternalWorkoutRecord(domain: summary))
        try context.save()

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SDExternalWorkoutRecord>()), 1)
        let stored = try XCTUnwrap(try context.fetch(FetchDescriptor<SDExternalWorkoutRecord>()).first)
        XCTAssertEqual(try stored.toDomain().idempotencyKey, "healthKit:fixture-1")
    }

    /// A fresh install (no prior store) must still open cleanly on V2.
    func testFreshInstallOpensOnVersionTwo() throws {
        let context = ModelContext(try openMigratedContainer())
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SDScheduledWorkout>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SDAppSettings>()), 0)
    }
}
