import Foundation
import SwiftData
import Observation
import EnduranceDomain

/// Owns a live session: the state machine, the clock, recovery, and the save
/// that follows (§G).
///
/// The session itself is injected as `ActiveWorkoutManaging`, so this entire
/// flow — including interruption recovery and duplicate prevention — is
/// exercised in tests with a deterministic fake and no watch, no HealthKit
/// authorization, and no waiting.
///
/// Every state change is written to `SDActiveWorkoutRecovery` **before** it is
/// acted on. A crash between deciding and persisting must lose nothing, and the
/// only way to guarantee that is to persist first.
@MainActor
@Observable
final class ActiveWorkoutCoordinator {

    /// Why a session could not continue, expressed without framework text (§P).
    enum Failure: String, Sendable {
        case sessionUnavailable
        case notAuthorized
        case startFailed
        case saveFailed
        case illegalTransition
    }

    private let session: any ActiveWorkoutManaging
    private let container: ModelContainer
    private let workoutStore: WorkoutStore
    private var context: ModelContext { container.mainContext }

    private(set) var machine = ActiveWorkoutMachine()
    private(set) var workout: ScheduledWorkout?
    private(set) var metrics = ActiveWorkoutMetrics()
    private(set) var lastFailure: Failure?
    private(set) var executionID: UUID?
    private(set) var currentStepIndex = 0
    private(set) var lapMarks: [TimeInterval] = []

    private var stopwatch = MonotonicStopwatch()
    private var startedAt: Date?
    private var tracker = IntervalTracker(steps: [])
    private var ticker: Task<Void, Never>?

    var state: ActiveWorkoutState { machine.state }
    var capability: ActiveWorkoutCapability { session.capability }

    /// A session that has been interrupted and not yet resolved.
    private(set) var recoverable: ActiveWorkoutRecovery?

    init(
        session: any ActiveWorkoutManaging,
        container: ModelContainer,
        workoutStore: WorkoutStore
    ) {
        self.session = session
        self.container = container
        self.workoutStore = workoutStore
    }

    // MARK: - Interval position

    var intervalProgress: IntervalProgress {
        tracker.progress(
            atIndex: currentStepIndex,
            elapsedInStep: elapsedInCurrentStep,
            distanceInStep: 0)
    }

    /// Elapsed inside the current step, measured from the lap mark that opened
    /// it. Laps and step boundaries are the same event here.
    private var elapsedInCurrentStep: TimeInterval {
        let stepStart = lapMarks.last ?? 0
        return max(0, metrics.activeSeconds - stepStart)
    }

    var availableFields: Set<ActiveWorkoutMetrics.Field> {
        guard let sport = workout?.sport else { return [.elapsed] }
        return capability.availableFields(for: sport)
    }

    // MARK: - Lifecycle

    func prepare(_ workout: ScheduledWorkout) async {
        guard machine.state == .idle else { return }
        self.workout = workout
        self.tracker = IntervalTracker(template: workoutStore.template(for: workout))
        self.executionID = UUID()
        self.currentStepIndex = 0
        self.lapMarks = []
        lastFailure = nil

        do {
            try machine.apply(.prepare)
            persistRecovery()
            try await session.prepare(for: workout)
        } catch {
            fail(.sessionUnavailable)
        }
    }

    func start() async {
        guard machine.canApply(.start) else { return }
        do {
            try machine.apply(.start)
            startedAt = Date()
            persistRecovery()

            try await session.start()
            stopwatch.start(now: DispatchTime.now().uptimeNanoseconds)
            try machine.apply(.sessionDidStart)
            persistRecovery()
            startTicking()
        } catch {
            fail(.startFailed)
        }
    }

    func pause() async {
        guard machine.canApply(.pause) else { return }
        do {
            try await session.pause()
            stopwatch.pause(now: DispatchTime.now().uptimeNanoseconds)
            try machine.apply(.pause)
            persistRecovery()
            stopTicking()
            await refreshMetrics()
        } catch {
            fail(.sessionUnavailable)
        }
    }

    func resume() async {
        guard machine.canApply(.resume) else { return }
        do {
            try machine.apply(.resume)
            try await session.resume()
            stopwatch.start(now: DispatchTime.now().uptimeNanoseconds)
            try machine.apply(.sessionDidResume)
            persistRecovery()
            startTicking()
        } catch {
            fail(.sessionUnavailable)
        }
    }

    /// Mark a lap, and advance the interval cursor with it.
    func markLap() async {
        guard state == .running else { return }
        await session.markLap()
        lapMarks.append(metrics.activeSeconds)
        if currentStepIndex < tracker.totalSteps { currentStepIndex += 1 }
        persistRecovery()
    }

    func end() async {
        guard machine.canApply(.end) else { return }
        stopTicking()
        do {
            try machine.apply(.end)
            persistRecovery()
            try await session.end()
            stopwatch.pause(now: DispatchTime.now().uptimeNanoseconds)
            try machine.apply(.sessionDidEnd)
            persistRecovery()
            await save()
        } catch {
            fail(.saveFailed)
        }
    }

    /// Save is separated from `end` so a failure is retryable without
    /// re-ending a session that has already stopped (§G: a failed save keeps
    /// the data).
    func save() async {
        guard state == .saving else { return }
        do {
            let execution = try await session.save()
            // Recorded through the merger, which collapses an execution already
            // represented rather than creating a twin (§O). The same session
            // arriving later from HealthKit import must not double it.
            workoutStore.recordExecution(execution)
            try machine.apply(.saveSucceeded)
            clearRecovery()
            await refreshMetrics()
        } catch {
            _ = try? machine.apply(.saveFailed)
            // Recovery is deliberately *kept*: the session is over but the data
            // is not yet safe, and discarding it here would be the data loss
            // the retry path exists to prevent.
            persistRecovery()
            lastFailure = .saveFailed
        }
    }

    func retrySave() async {
        guard machine.canApply(.retry) else { return }
        _ = try? machine.apply(.retry)
        await save()
    }

    /// Discard. Callers confirm first — this does not ask.
    func discard() async {
        guard machine.canApply(.discard) else { return }
        stopTicking()
        _ = try? await session.discard()
        _ = try? machine.apply(.discard)
        clearRecovery()
    }

    // MARK: - Interruption recovery (§G)

    /// Look for a session that was live when the app stopped.
    ///
    /// Called at launch. A record whose state was still active means the app
    /// died mid-session, and the athlete is owed a decision about it rather than
    /// silent deletion of work they actually did.
    func checkForInterruptedSession() {
        let rows = (try? context.fetch(FetchDescriptor<SDActiveWorkoutRecovery>())) ?? []
        let candidates = rows.compactMap { try? $0.toDomain() }.filter(\.needsRecovery)
        recoverable = candidates.sorted { $0.updatedAt > $1.updatedAt }.first
    }

    /// Resume an interrupted session, restoring accrued time.
    func recoverInterrupted(_ recovery: ActiveWorkoutRecovery) async {
        machine = ActiveWorkoutMachine(state: .recovering)
        executionID = recovery.executionID
        currentStepIndex = recovery.currentStepIndex
        startedAt = recovery.startedAt
        // Time already banked is restored; the clock resumes from there rather
        // than from zero, so an interruption does not erase the session.
        stopwatch = MonotonicStopwatch(accumulated: recovery.accumulatedSeconds)

        if let id = recovery.scheduledWorkoutID,
           let match = workoutStore.allWorkouts.first(where: { $0.id == id }) {
            workout = match
            tracker = IntervalTracker(template: workoutStore.template(for: match))
        }

        do {
            try machine.apply(.recovered)
            stopwatch.start(now: DispatchTime.now().uptimeNanoseconds)
            persistRecovery()
            startTicking()
            recoverable = nil
        } catch {
            fail(.illegalTransition)
        }
    }

    /// End an interrupted session without resuming it: keep what was accrued and
    /// save it. The athlete did the work; the app losing track is not their
    /// problem to absorb.
    func saveInterrupted(_ recovery: ActiveWorkoutRecovery) async {
        machine = ActiveWorkoutMachine(state: .recovering)
        executionID = recovery.executionID
        startedAt = recovery.startedAt
        stopwatch = MonotonicStopwatch(accumulated: recovery.accumulatedSeconds)

        let execution = WorkoutExecution(
            id: recovery.executionID,
            scheduledWorkoutID: recovery.scheduledWorkoutID,
            source: .appTimer,
            start: recovery.startedAt,
            durationSeconds: Int(recovery.accumulatedSeconds),
            distanceMeters: nil,
            averageHeartRate: nil,
            activeEnergyKilocalories: nil,
            externalKeys: [],
            exportedProviderID: nil,
            recordedAt: Date())
        workoutStore.recordExecution(execution)

        _ = try? machine.apply(.end)
        _ = try? machine.apply(.sessionDidEnd)
        _ = try? machine.apply(.saveSucceeded)
        clearRecovery()
        recoverable = nil
    }

    func discardInterrupted(_ recovery: ActiveWorkoutRecovery) {
        deleteRecovery(executionID: recovery.executionID)
        recoverable = nil
    }

    // MARK: - Metrics

    /// Ticks once a second while running (§G: "do not calculate metrics more
    /// frequently than needed"). A live session pushes its own samples; this
    /// only advances the clock and asks for the latest values.
    private func startTicking() {
        stopTicking()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                await self.refreshMetrics()
                guard self.state.isAccruingTime else { return }
            }
        }
    }

    private func stopTicking() {
        ticker?.cancel()
        ticker = nil
    }

    private func refreshMetrics() async {
        var latest = await session.currentMetrics()
        let now = DispatchTime.now().uptimeNanoseconds
        latest.activeSeconds = stopwatch.elapsed(now: now)
        latest.elapsedSeconds = startedAt.map { Date().timeIntervalSince($0) } ?? latest.activeSeconds
        latest.averagePaceSecondsPerKilometre = ActiveWorkoutMetrics.pace(
            distanceMeters: latest.distanceMeters, activeSeconds: latest.activeSeconds)
        latest.averageSpeedMetresPerSecond = ActiveWorkoutMetrics.speed(
            distanceMeters: latest.distanceMeters, activeSeconds: latest.activeSeconds)
        metrics = latest
        persistRecovery()
    }

    // MARK: - Persistence

    private func persistRecovery() {
        guard let executionID, let startedAt else { return }
        // A finished session is not recoverable. Without this, the metrics
        // refresh that follows a successful save re-created the row that `save`
        // had just cleared, and the next launch would offer to "recover" a
        // session already written — inviting exactly the duplicate §O forbids.
        guard !machine.state.isTerminal else { return }
        let recovery = ActiveWorkoutRecovery(
            scheduledWorkoutID: workout?.id,
            executionID: executionID,
            state: machine.state,
            sport: workout?.sport ?? .recovery,
            startedAt: startedAt,
            accumulatedSeconds: stopwatch.elapsed(now: DispatchTime.now().uptimeNanoseconds),
            currentStepIndex: currentStepIndex,
            updatedAt: Date())
        do {
            let rows = (try? context.fetch(FetchDescriptor<SDActiveWorkoutRecovery>())) ?? []
            if let existing = rows.first(where: { $0.executionID == executionID }) {
                try existing.update(recovery)
            } else {
                context.insert(try SDActiveWorkoutRecovery(domain: recovery))
            }
            try context.save()
        } catch {
            AppLog.persistence.error("Active workout recovery write failed: \(error)")
        }
    }

    private func clearRecovery() {
        guard let executionID else { return }
        deleteRecovery(executionID: executionID)
    }

    private func deleteRecovery(executionID: UUID) {
        let rows = (try? context.fetch(FetchDescriptor<SDActiveWorkoutRecovery>())) ?? []
        for row in rows where row.executionID == executionID { context.delete(row) }
        try? context.save()
    }

    private func fail(_ failure: Failure) {
        lastFailure = failure
        stopTicking()
        _ = try? machine.apply(.saveFailed)
        AppLog.app.error("Active workout failed: \(failure.rawValue, privacy: .public)")
    }

    /// Reset to idle once a session is finished with, so the next one starts clean.
    func reset() {
        stopTicking()
        machine = ActiveWorkoutMachine()
        workout = nil
        metrics = ActiveWorkoutMetrics()
        executionID = nil
        startedAt = nil
        currentStepIndex = 0
        lapMarks = []
        stopwatch = MonotonicStopwatch()
        lastFailure = nil
    }
}
