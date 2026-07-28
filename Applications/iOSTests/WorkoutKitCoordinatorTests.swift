import XCTest
import SwiftData
import EnduranceDomain
import EnduranceWorkoutKit
import EnduranceTrainingPlans
@testable import Endurance

/// §I at the app layer, through a deterministic fake scheduler.
///
/// The behaviours worth pinning down are the ones that protect what is on the
/// athlete's wrist: only an upcoming window is sent, a simplification needs
/// consent for *that* simplification, and a session that is completed, moved or
/// skipped does not leave a stale structured workout behind.
@MainActor
final class WorkoutKitCoordinatorTests: XCTestCase {

    // MARK: - Fake scheduler

    private final class FakeScheduler: WorkoutScheduling, @unchecked Sendable {
        var supported = true
        var authorization: WorkoutSchedulingAuthorization = .authorized
        var scheduleError: WorkoutKitSchedulingError?
        var removeError: WorkoutKitSchedulingError?

        private(set) var scheduled: [UUID: WorkoutKitScheduleRequest] = [:]
        private(set) var scheduleCalls = 0
        private(set) var removeCalls = 0
        private(set) var removeAllCalls = 0
        /// Plans the system reports, for reconciliation tests.
        var systemPlans: [WorkoutKitScheduledPlan]?

        var isSupported: Bool { supported }
        func authorizationState() async -> WorkoutSchedulingAuthorization { authorization }
        func requestAuthorization() async -> WorkoutSchedulingAuthorization { authorization }

        func schedule(_ request: WorkoutKitScheduleRequest) async throws {
            scheduleCalls += 1
            if let scheduleError { throw scheduleError }
            scheduled[request.scheduledWorkoutID] = request
        }

        func remove(_ request: WorkoutKitScheduleRequest) async throws {
            removeCalls += 1
            if let removeError { throw removeError }
            scheduled[request.scheduledWorkoutID] = nil
        }

        func scheduledPlans() async throws -> [WorkoutKitScheduledPlan] {
            if let systemPlans { return systemPlans }
            return scheduled.values.map {
                WorkoutKitScheduledPlan(workoutPlanID: $0.workoutPlanID, plannedStart: $0.plannedStart)
            }
        }

        func removeAllEndurancePlans() async throws {
            removeAllCalls += 1
            scheduled.removeAll()
        }
    }

    private var container: ModelContainer!
    private var store: WorkoutStore!
    private var scheduler: FakeScheduler!
    private var coordinator: WorkoutKitCoordinator!

    private var defaultsSuite: String!

    override func setUp() async throws {
        // Never touch UserDefaults.standard from tests: the integration
        // toggles are persisted there, and a leaked value silently changes
        // another test's starting state.
        defaultsSuite = "test.\(UUID().uuidString)"
        let config = ModelConfiguration(schema: EnduranceSchema.current, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: EnduranceSchema.current, configurations: [config])
        store = WorkoutStore(modelContainer: container)
        try store.completeOnboarding(
            configuration: ScheduleConfiguration(
                anchor: .startDate(Calendar.current.startOfDay(for: Date())),
                timeZoneIdentifier: TimeZone.current.identifier),
            units: .metric,
            preferences: NotificationPreferences(),
            raceName: nil,
            raceLocation: nil)

        scheduler = FakeScheduler()
        coordinator = WorkoutKitCoordinator(
            scheduler: scheduler, container: container, workoutStore: store,
            preferencesStore: IntegrationPreferencesStore(
                defaults: UserDefaults(suiteName: defaultsSuite)!))
        await coordinator.refreshAuthorization()
    }

    override func tearDown() async throws {
        if let defaultsSuite { UserDefaults.standard.removePersistentDomain(forName: defaultsSuite) }
        coordinator = nil
        scheduler = nil
        store = nil
        container = nil
    }

    /// The next planned session the converter can actually schedule.
    ///
    /// Day one of the bundled plan is mobility, which WorkoutKit cannot
    /// represent, so tests that need a *schedulable* session must ask for one
    /// rather than assume the next session qualifies.
    private func nextSchedulable() throws -> ScheduledWorkout {
        let candidate = store.allWorkouts
            .filter { $0.status == .planned && $0.plannedStart >= Date() }
            .sorted { $0.plannedStart < $1.plannedStart }
            .first { coordinator.conversion(for: $0).outcome == .exact }
        return try XCTUnwrap(candidate, "the bundled plan should contain an exact conversion")
    }

    private func nextPlanned() throws -> ScheduledWorkout {
        let all = store.allWorkouts
            .filter { $0.status == .planned && $0.plannedStart >= Date() }
            .sorted { $0.plannedStart < $1.plannedStart }
        return try XCTUnwrap(all.first)
    }

    // MARK: - Nothing happens unasked

    func testNothingIsScheduledWhileDisabled() async {
        await coordinator.synchronize()
        XCTAssertEqual(scheduler.scheduleCalls, 0,
                       "scheduling is off by default and must not push anything")
    }

    func testEnablingRequestsAuthorizationAndSynchronizes() async throws {
        // The default `.nextWorkout` horizon schedules exactly one session, and
        // whether that session is convertible depends on which weekday the suite
        // runs — day one of the bundled plan is mobility, which WorkoutKit
        // cannot represent. This test was therefore green on some days and red
        // on others, with nothing in the product changing. Widen the horizon so
        // it asserts what it means to assert: that enabling requests
        // authorization and then actually synchronizes.
        coordinator.preferences.horizon = .days7
        let schedulable = try XCTUnwrap(
            store.allWorkouts
                .filter {
                    $0.status == .planned
                        && $0.plannedStart >= Date()
                        && $0.plannedStart <= Date().addingTimeInterval(7 * 86_400)
                }
                .sorted { $0.plannedStart < $1.plannedStart }
                .first { coordinator.conversion(for: $0).outcome.isSchedulable },
            "a 7-day window of the bundled plan must contain a schedulable session")

        await coordinator.enableScheduling()

        XCTAssertTrue(coordinator.preferences.isEnabled)
        XCTAssertGreaterThan(scheduler.scheduleCalls, 0)
        XCTAssertNotNil(scheduler.scheduled[schedulable.id],
                        "the schedulable session in the window should have been sent")
    }

    func testDeniedAuthorizationSchedulesNothing() async {
        scheduler.authorization = .denied
        await coordinator.enableScheduling()

        XCTAssertFalse(coordinator.preferences.isEnabled)
        XCTAssertEqual(scheduler.scheduleCalls, 0)
    }

    func testUnsupportedDeviceReportsUnavailableWithoutScheduling() async {
        scheduler.supported = false
        await coordinator.refreshAuthorization()
        await coordinator.enableScheduling()

        XCTAssertEqual(coordinator.authorization, .unavailable)
        XCTAssertEqual(scheduler.scheduleCalls, 0)
    }

    // MARK: - Only an upcoming window

    func testTheNextWorkoutHorizonSendsAtMostOneSession() async throws {
        coordinator.preferences.horizon = .nextWorkout
        await coordinator.enableScheduling()

        XCTAssertLessThanOrEqual(scheduler.scheduled.count, 1,
                                 "the narrowest horizon sends one session, not 382")
    }

    /// Day one of the bundled plan is mobility, which cannot be represented, so
    /// "next session only" legitimately sends nothing that day. The settings
    /// preview shows why rather than leaving it unexplained.
    func testAnUnrepresentableNextSessionSendsNothingAndSaysSo() async throws {
        coordinator.preferences.horizon = .nextWorkout
        await coordinator.enableScheduling()

        let next = try nextPlanned()
        if coordinator.conversion(for: next).outcome == .unsupported {
            XCTAssertNil(scheduler.scheduled[next.id])
            XCTAssertEqual(coordinator.status(for: next), .unsupported)
        }
    }

    func testAWiderHorizonSendsMoreButStillBounded() async throws {
        coordinator.preferences.horizon = .days7
        await coordinator.enableScheduling()

        let count = scheduler.scheduled.count
        XCTAssertGreaterThan(count, 1)
        XCTAssertLessThan(count, 40, "a 7-day horizon must not approach the whole plan")
        XCTAssertLessThan(count, store.allWorkouts.count)
    }

    func testCompletedSessionsAreNeverScheduled() async throws {
        coordinator.preferences.horizon = .days7
        let workout = try nextSchedulable()
        try store.complete(workout.id, completion: WorkoutCompletion(completedAt: Date(), source: .manual))

        await coordinator.enableScheduling()

        XCTAssertNil(scheduler.scheduled[workout.id],
                     "a finished session must never be pushed to the Watch")
    }

    // MARK: - Consent for simplifications

    func testExactConversionsScheduleWithoutAsking() async throws {
        await coordinator.enableScheduling()
        let scheduledIDs = Set(scheduler.scheduled.keys)

        for id in scheduledIDs {
            let workout = try XCTUnwrap(store.workout(id: id))
            XCTAssertEqual(coordinator.conversion(for: workout).outcome, .exact,
                           "only exact conversions may be sent automatically")
        }
    }

    func testSimplifiedConversionsWaitForApproval() async throws {
        coordinator.preferences.horizon = .days14
        await coordinator.enableScheduling()

        // Find a session the converter simplifies.
        let simplified = store.allWorkouts
            .filter { $0.status == .planned && $0.plannedStart >= Date() }
            .first { coordinator.conversion(for: $0).outcome == .simplified }

        guard let simplified else {
            throw XCTSkip("No simplified conversion in the horizon for this plan.")
        }
        XCTAssertNil(scheduler.scheduled[simplified.id],
                     "a lossy conversion must not be sent without consent")
        XCTAssertEqual(coordinator.status(for: simplified), .simplifiedAvailable)

        await coordinator.approveSimplification(for: simplified)
        XCTAssertNotNil(scheduler.scheduled[simplified.id])
        XCTAssertEqual(coordinator.status(for: simplified), .scheduled)
    }

    func testUnsupportedSessionsAreRecordedNotSent() async throws {
        coordinator.preferences.horizon = .days14
        await coordinator.enableScheduling()

        let unsupported = store.allWorkouts
            .filter { $0.status == .planned && $0.plannedStart >= Date() }
            .first { coordinator.conversion(for: $0).outcome == .unsupported }

        guard let unsupported else {
            throw XCTSkip("No unsupported conversion in the horizon for this plan.")
        }
        XCTAssertNil(scheduler.scheduled[unsupported.id])
        XCTAssertEqual(coordinator.status(for: unsupported), .unsupported,
                       "an unsupported session must say so, not look scheduled")
    }

    // MARK: - Idempotency

    func testRepeatedSynchronizationDoesNotReschedule() async throws {
        await coordinator.enableScheduling()
        let first = scheduler.scheduleCalls

        await coordinator.synchronize()
        XCTAssertEqual(scheduler.scheduleCalls, first,
                       "an unchanged session must not be re-sent on every sync")
    }

    // MARK: - Reconciliation after plan changes

    func testCompletingASessionRemovesItFromTheWatch() async throws {
        coordinator.preferences.horizon = .days7
        await coordinator.enableScheduling()
        let workout = try nextSchedulable()
        XCTAssertNotNil(scheduler.scheduled[workout.id])

        try store.complete(workout.id, completion: WorkoutCompletion(completedAt: Date(), source: .manual))
        await coordinator.reconcileAfterPlanChange(scheduledWorkoutID: workout.id)

        XCTAssertNil(scheduler.scheduled[workout.id],
                     "a completed session must not stay on the Watch")
    }

    func testSkippingASessionRemovesItFromTheWatch() async throws {
        coordinator.preferences.horizon = .days7
        await coordinator.enableScheduling()
        let workout = try nextSchedulable()

        try store.skip(workout.id, reason: nil)
        await coordinator.reconcileAfterPlanChange(scheduledWorkoutID: workout.id)

        XCTAssertNil(scheduler.scheduled[workout.id])
    }

    func testMovingASessionUpdatesTheScheduledDate() async throws {
        coordinator.preferences.horizon = .days7
        await coordinator.enableScheduling()
        let workout = try nextSchedulable()
        let originalStart = try XCTUnwrap(scheduler.scheduled[workout.id]).plannedStart

        let newDate = Calendar.current.date(byAdding: .day, value: 2, to: workout.scheduledDate)!
        try store.reschedule(workout.id, to: newDate)
        await coordinator.reconcileAfterPlanChange(scheduledWorkoutID: workout.id)

        // Rescheduling makes it .rescheduled, not .planned, so it leaves the Watch.
        XCTAssertNil(scheduler.scheduled[workout.id],
                     "a moved session must not keep its old slot on the Watch")
        XCTAssertGreaterThan(scheduler.removeCalls, 0)
        XCTAssertNotNil(originalStart)
    }

    func testDisablingRemovesEverything() async throws {
        coordinator.preferences.horizon = .days7
        await coordinator.enableScheduling()
        XCTAssertFalse(scheduler.scheduled.isEmpty)

        await coordinator.disableScheduling()
        XCTAssertTrue(scheduler.scheduled.isEmpty)
        XCTAssertEqual(scheduler.removeAllCalls, 1)
    }

    // MARK: - Failure handling

    func testScheduleFailureIsRecordedAndRetryable() async throws {
        coordinator.preferences.horizon = .days7
        await coordinator.refreshAuthorization()
        let workout = try nextSchedulable()

        scheduler.scheduleError = .scheduleFailed
        await coordinator.enableScheduling()
        XCTAssertEqual(coordinator.status(for: workout), .failedRetryable)
        XCTAssertEqual(coordinator.lastFailure, .scheduleFailed)

        // The plan itself is untouched.
        XCTAssertEqual(store.allWorkouts.count, 382)
    }

    func testPermanentFailureIsNotMarkedRetryable() async throws {
        coordinator.preferences.horizon = .days7
        await coordinator.refreshAuthorization()
        let workout = try nextSchedulable()

        scheduler.scheduleError = .unsupportedGoal
        await coordinator.enableScheduling()
        XCTAssertEqual(coordinator.status(for: workout), .failedPermanent)
    }

    // MARK: - System reconciliation (§I)

    func testASchedulingCallThatSucceededWhileWeDiedIsReconciled() async throws {
        coordinator.preferences.horizon = .days7
        await coordinator.enableScheduling()
        let workout = try nextSchedulable()

        // Simulate: our record says "scheduling", the system says it is live.
        var record = try XCTUnwrap(coordinator.record(for: workout.id))
        let identifier = record.schedulingIdentifier
        record.status = .scheduling
        let context = ModelContext(container)
        if let row = try context.fetch(FetchDescriptor<SDWorkoutKitScheduleRecord>())
            .first(where: { $0.scheduledWorkoutID == workout.id }) {
            try row.update(record)
            try context.save()
        }
        scheduler.systemPlans = [
            WorkoutKitScheduledPlan(workoutPlanID: try XCTUnwrap(UUID(uuidString: identifier)),
                                    plannedStart: workout.plannedStart)
        ]

        await coordinator.reconcileWithSystem()

        XCTAssertEqual(coordinator.record(for: workout.id)?.status, .scheduled,
                       "a framework call that succeeded must not stay recorded as in-flight")
    }

    func testARecordClaimingScheduledIsCorrectedWhenTheSystemDisagrees() async throws {
        coordinator.preferences.horizon = .days7
        await coordinator.enableScheduling()
        let workout = try nextSchedulable()
        XCTAssertEqual(coordinator.record(for: workout.id)?.status, .scheduled)

        // The system no longer has it — e.g. the athlete removed it on the Watch.
        scheduler.systemPlans = []
        await coordinator.reconcileWithSystem()

        XCTAssertEqual(coordinator.record(for: workout.id)?.status, .removed,
                       "Endurance must not claim something is on the Watch when it is not")
    }

    // MARK: - Staleness

    func testARecordFromAnOlderConverterReportsStale() async throws {
        coordinator.preferences.horizon = .days7
        await coordinator.enableScheduling()
        let workout = try nextSchedulable()

        var record = try XCTUnwrap(coordinator.record(for: workout.id))
        record.conversionVersion = WorkoutKitConversionResult.currentVersion - 1
        let context = ModelContext(container)
        if let row = try context.fetch(FetchDescriptor<SDWorkoutKitScheduleRecord>())
            .first(where: { $0.scheduledWorkoutID == workout.id }) {
            try row.update(record)
            try context.save()
        }

        XCTAssertEqual(coordinator.status(for: workout), .stale,
                       "a schedule built by an older converter must be refreshed, not trusted")
    }
    // MARK: - Explicit send (regression)

    /// The bug: the workout screen's "Send to Apple Watch" called
    /// `synchronize()`, which opens with `guard preferences.isEnabled` and only
    /// ever schedules the horizon window. Before scheduling was switched on in
    /// Settings — or for any session outside the window — the button did
    /// nothing at all. No error, no state change, no explanation.
    func testSendingASessionWorksEvenWhenSchedulingWasNeverEnabled() async throws {
        XCTAssertFalse(coordinator.preferences.isEnabled, "precondition: never enabled")

        let workout = try nextSchedulable()
        let sent = await coordinator.scheduleNow(workout)

        XCTAssertTrue(sent, "an explicit request must schedule, not silently no-op")
        XCTAssertEqual(coordinator.status(for: workout), .scheduled)
        XCTAssertTrue(coordinator.preferences.isEnabled,
                      "sending implies the feature is wanted; otherwise the next sync removes it")
    }

    /// A session outside the horizon must still send when asked for directly.
    func testSendingWorksForASessionOutsideTheHorizon() async throws {
        coordinator.preferences.horizon = .nextWorkout
        await coordinator.enableScheduling()

        let candidates = store.allWorkouts
            .filter { $0.status == .planned && $0.plannedStart >= Date() }
            .sorted { $0.plannedStart < $1.plannedStart }
        let distant = try XCTUnwrap(
            candidates.dropFirst(5).first { coordinator.conversion(for: $0).outcome.isSchedulable },
            "need a schedulable session well outside a next-workout horizon")

        let sent = await coordinator.scheduleNow(distant)
        XCTAssertTrue(sent, "the horizon governs automatic sync, not an explicit request")
    }

    /// Denied authorization must report, not fail silently.
    ///
    /// The denial has to be observed through a refresh, because that is how it
    /// reaches the coordinator in practice — `authorization` is cached, and a
    /// revocation in Settings is discovered when the state is next read.
    func testDeniedAuthorizationOnExplicitSendIsReported() async throws {
        scheduler.authorization = .denied
        await coordinator.refreshAuthorization()
        let workout = try nextSchedulable()

        let sent = await coordinator.scheduleNow(workout)
        XCTAssertFalse(sent)
        XCTAssertEqual(coordinator.lastFailure, .authorizationRequired)
    }

}
