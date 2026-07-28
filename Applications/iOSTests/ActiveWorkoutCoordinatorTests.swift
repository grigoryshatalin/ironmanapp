import XCTest
import SwiftData
import EnduranceDomain
import EnduranceTrainingPlans
@testable import Endurance

/// §G at the app layer, through a deterministic fake session.
///
/// The behaviours worth pinning are the ones that protect work the athlete has
/// already done: a crash mid-session must not erase it, a failed save must stay
/// retryable rather than silently dropping the data, and a saved session must
/// not become a second copy when the same workout later arrives from HealthKit.
@MainActor
final class ActiveWorkoutCoordinatorTests: XCTestCase {

    // MARK: - Fake session

    private final class FakeSession: ActiveWorkoutManaging, @unchecked Sendable {
        var state: ActiveWorkoutState = .idle
        var capability = ActiveWorkoutCapability.timingOnly
        var metrics = ActiveWorkoutMetrics()
        var saveError: Error?
        var startError: Error?
        private(set) var lapCount = 0
        private(set) var didDiscard = false
        var executionToReturn: WorkoutExecution?

        func prepare(for workout: ScheduledWorkout) async throws { state = .preparing }
        func start() async throws {
            if let startError { throw startError }
            state = .running
        }
        func pause() async throws { state = .paused }
        func resume() async throws { state = .running }
        func end() async throws { state = .saving }
        func markLap() async { lapCount += 1 }
        func currentMetrics() async -> ActiveWorkoutMetrics { metrics }
        func discard() async throws { didDiscard = true; state = .discarded }

        func save() async throws -> WorkoutExecution {
            if let saveError { throw saveError }
            state = .completed
            return executionToReturn ?? WorkoutExecution(
                id: UUID(), scheduledWorkoutID: nil, source: .appTimer,
                start: Date(), durationSeconds: 600, distanceMeters: nil,
                averageHeartRate: nil, activeEnergyKilocalories: nil,
                externalKeys: [], exportedProviderID: nil, recordedAt: Date())
        }
    }

    private struct StubError: Error {}

    private var container: ModelContainer!
    private var store: WorkoutStore!
    private var session: FakeSession!
    private var coordinator: ActiveWorkoutCoordinator!

    override func setUp() async throws {
        let config = ModelConfiguration(schema: EnduranceSchema.current, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: EnduranceSchema.current, configurations: [config])
        store = WorkoutStore(modelContainer: container)
        try store.completeOnboarding(
            configuration: ScheduleConfiguration(
                anchor: .startDate(Calendar.current.startOfDay(for: Date())),
                timeZoneIdentifier: TimeZone.current.identifier),
            units: .metric,
            preferences: NotificationPreferences(),
            raceName: nil, raceLocation: nil)
        session = FakeSession()
        coordinator = ActiveWorkoutCoordinator(
            session: session, container: container, workoutStore: store)
    }

    override func tearDown() async throws {
        coordinator = nil; session = nil; store = nil; container = nil
    }

    private func aWorkout() throws -> ScheduledWorkout {
        try XCTUnwrap(store.allWorkouts.sorted { $0.plannedStart < $1.plannedStart }.first)
    }

    // MARK: - Lifecycle

    func testHappyPathReachesCompleted() async throws {
        let workout = try aWorkout()
        await coordinator.prepare(workout)
        XCTAssertEqual(coordinator.state, .preparing)

        await coordinator.start()
        XCTAssertEqual(coordinator.state, .running)

        await coordinator.pause()
        XCTAssertEqual(coordinator.state, .paused)

        await coordinator.resume()
        XCTAssertEqual(coordinator.state, .running)

        await coordinator.end()
        XCTAssertEqual(coordinator.state, .completed)
    }

    func testDiscardLeavesNoExecution() async throws {
        await coordinator.prepare(try aWorkout())
        await coordinator.start()
        await coordinator.discard()

        XCTAssertEqual(coordinator.state, .discarded)
        XCTAssertTrue(session.didDiscard)
        let executions = try container.mainContext.fetch(FetchDescriptor<SDWorkoutExecution>())
        XCTAssertTrue(executions.isEmpty, "a discarded session must record nothing")
    }

    // MARK: - Recovery (§G)

    func testAnInterruptedSessionIsOfferedBackAndNotSilentlyLost() async throws {
        await coordinator.prepare(try aWorkout())
        await coordinator.start()

        // A crash: state was persisted, the coordinator never finished.
        let fresh = ActiveWorkoutCoordinator(
            session: FakeSession(), container: container, workoutStore: store)
        fresh.checkForInterruptedSession()

        let recovered = try XCTUnwrap(
            fresh.recoverable,
            "a session that was running when the app died must be offered back")
        XCTAssertTrue(recovered.needsRecovery)
    }

    func testSavingAnInterruptedSessionKeepsTheAccruedTime() async throws {
        await coordinator.prepare(try aWorkout())
        await coordinator.start()

        let fresh = ActiveWorkoutCoordinator(
            session: FakeSession(), container: container, workoutStore: store)
        fresh.checkForInterruptedSession()
        let recovery = try XCTUnwrap(fresh.recoverable)
        await fresh.saveInterrupted(recovery)

        let executions = try container.mainContext.fetch(FetchDescriptor<SDWorkoutExecution>())
        XCTAssertEqual(executions.count, 1, "the athlete did the work; it must be kept")
        XCTAssertNil(fresh.recoverable)
    }

    func testDiscardingAnInterruptedSessionClearsIt() async throws {
        await coordinator.prepare(try aWorkout())
        await coordinator.start()

        let fresh = ActiveWorkoutCoordinator(
            session: FakeSession(), container: container, workoutStore: store)
        fresh.checkForInterruptedSession()
        let recovery = try XCTUnwrap(fresh.recoverable)
        fresh.discardInterrupted(recovery)

        XCTAssertNil(fresh.recoverable)
        let rows = try container.mainContext.fetch(FetchDescriptor<SDActiveWorkoutRecovery>())
        XCTAssertTrue(rows.isEmpty)
    }

    func testACompletedSessionLeavesNoRecoveryRecord() async throws {
        await coordinator.prepare(try aWorkout())
        await coordinator.start()
        await coordinator.end()

        let rows = try container.mainContext.fetch(FetchDescriptor<SDActiveWorkoutRecovery>())
        XCTAssertTrue(rows.isEmpty, "a finished session must not be offered as recoverable")
    }

    // MARK: - Failed save keeps the data

    func testAFailedSaveStaysRetryableAndKeepsRecovery() async throws {
        session.saveError = StubError()
        await coordinator.prepare(try aWorkout())
        await coordinator.start()
        await coordinator.end()

        XCTAssertEqual(coordinator.state, .failed)
        XCTAssertEqual(coordinator.lastFailure, .saveFailed)

        let rows = try container.mainContext.fetch(FetchDescriptor<SDActiveWorkoutRecovery>())
        XCTAssertFalse(rows.isEmpty, "a failed save must keep the data, not discard it")

        session.saveError = nil
        await coordinator.retrySave()
        XCTAssertEqual(coordinator.state, .completed)
    }

    // MARK: - Duplicate prevention (§O)

    func testTheSameExecutionRecordedTwiceDoesNotDouble() async throws {
        let execution = WorkoutExecution(
            id: UUID(), scheduledWorkoutID: try aWorkout().id, source: .appTimer,
            start: Date(), durationSeconds: 1800, distanceMeters: nil,
            averageHeartRate: nil, activeEnergyKilocalories: nil,
            externalKeys: [], exportedProviderID: nil, recordedAt: Date())

        store.recordExecution(execution)
        store.recordExecution(execution)

        let rows = try container.mainContext.fetch(FetchDescriptor<SDWorkoutExecution>())
        XCTAssertEqual(rows.count, 1, "the same session observed twice is one session")
    }

    // MARK: - Capability honesty

    func testAPhoneOnlySessionDoesNotOfferHeartRate() async throws {
        await coordinator.prepare(try aWorkout())
        XCTAssertFalse(coordinator.availableFields.contains(.heartRate),
                       "an iPhone without a Watch has no heart rate to show")
        XCTAssertTrue(coordinator.availableFields.contains(.elapsed))
    }

    // MARK: - Interval position

    func testMarkingALapAdvancesTheIntervalCursor() async throws {
        await coordinator.prepare(try aWorkout())
        await coordinator.start()
        let before = coordinator.intervalProgress.currentIndex
        await coordinator.markLap()
        XCTAssertEqual(coordinator.intervalProgress.currentIndex, before + 1)
        XCTAssertEqual(session.lapCount, 1)
    }
}
