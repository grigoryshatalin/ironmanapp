import Foundation
import SwiftData
import Observation
import EnduranceDomain
import EnduranceWorkoutKit

/// Owns WorkoutKit scheduling for the app (§I).
///
/// Three rules shape this:
///
///   1. **Only an upcoming window is scheduled.** The plan has 382 sessions;
///      pushing all of them at the Workout app would be both wasteful and
///      misleading, since the plan changes as the athlete trains.
///   2. **Exact conversions schedule automatically; simplified ones do not.**
///      A simplification is approved against its *fingerprint*, so a later,
///      different simplification of the same session needs fresh consent rather
///      than inheriting the old one.
///   3. **Plan changes reconcile.** Completing, skipping, moving, shortening or
///      replacing a session updates or removes what is on the Watch. A stale
///      structured workout sitting on someone's wrist is worse than none.
///
/// The scheduler is injected as a protocol, so all of this is exercised in tests
/// with a deterministic fake and no device.
@MainActor
@Observable
final class WorkoutKitCoordinator {

    private let scheduler: any WorkoutScheduling
    private let converter = WorkoutKitConverter()
    private let container: ModelContainer
    private let workoutStore: WorkoutStore

    private(set) var authorization: WorkoutSchedulingAuthorization = .notDetermined
    private(set) var isSynchronizing = false
    private(set) var lastFailure: WorkoutKitFailureCategory?

    /// Athlete preferences. Off by default — nothing is scheduled unasked.
    var preferences = WorkoutKitSchedulingPreferences()

    init(
        scheduler: any WorkoutScheduling,
        container: ModelContainer,
        workoutStore: WorkoutStore
    ) {
        self.scheduler = scheduler
        self.container = container
        self.workoutStore = workoutStore
    }

    private var context: ModelContext { container.mainContext }

    static func defaultScheduler() -> any WorkoutScheduling {
        #if canImport(WorkoutKit) && canImport(HealthKit)
        if #available(iOS 17.0, watchOS 10.0, *) {
            return WorkoutKitSchedulerAdapter()
        }
        return UnavailableWorkoutKitScheduler()
        #else
        return UnavailableWorkoutKitScheduler()
        #endif
    }

    var isSupported: Bool { scheduler.isSupported }

    // MARK: - Authorization

    func refreshAuthorization() async {
        guard scheduler.isSupported else {
            authorization = .unavailable
            return
        }
        authorization = await scheduler.authorizationState()
    }

    /// Requested only when the athlete turns scheduling on (§I).
    func enableScheduling() async {
        guard scheduler.isSupported else {
            authorization = .unavailable
            return
        }
        authorization = await scheduler.requestAuthorization()
        preferences.isEnabled = authorization == .authorized
        if preferences.isEnabled { await synchronize() }
    }

    func disableScheduling() async {
        preferences.isEnabled = false
        await removeAllScheduled()
    }

    // MARK: - Preview

    /// What would happen to this session, without scheduling anything. Drives
    /// the preview UI so an athlete can see a simplification before consenting.
    func conversion(for workout: ScheduledWorkout) -> WorkoutKitConversionResult {
        converter.convert(workout, template: workoutStore.template(for: workout))
    }

    func record(for scheduledWorkoutID: UUID) -> WorkoutKitScheduleRecord? {
        rows().first { $0.scheduledWorkoutID == scheduledWorkoutID }
            .flatMap { try? $0.toDomain() }
    }

    /// The status a view renders. Views never derive this themselves.
    func status(for workout: ScheduledWorkout) -> WorkoutKitScheduleStatus {
        if let stored = record(for: workout.id) {
            // A stored schedule produced by an older converter is stale, not
            // scheduled — refreshing it is the honest answer.
            if stored.conversionVersion < WorkoutKitConversionResult.currentVersion {
                return .stale
            }
            return stored.status
        }
        guard scheduler.isSupported else { return .unsupported }
        guard authorization == .authorized else { return .authorizationRequired }
        switch conversion(for: workout).outcome {
        case .exact: return .exactAvailable
        case .simplified: return .simplifiedAvailable
        case .unsupported: return .unsupported
        }
    }

    // MARK: - Synchronization

    /// Schedule the upcoming window and remove anything that no longer belongs.
    func synchronize(now: Date = Date()) async {
        guard preferences.isEnabled, scheduler.isSupported, !isSynchronizing else { return }
        guard authorization == .authorized else {
            lastFailure = .authorizationRequired
            return
        }
        isSynchronizing = true
        defer { isSynchronizing = false }

        let window = upcomingWindow(now: now)
        let windowIDs = Set(window.map(\.id))

        // 1. Remove anything scheduled that has left the window, been completed,
        //    skipped, replaced, or moved out of range.
        for stored in rows().compactMap({ try? $0.toDomain() })
        where stored.status == .scheduled && !windowIDs.contains(stored.scheduledWorkoutID) {
            await remove(scheduledWorkoutID: stored.scheduledWorkoutID)
        }

        // 2. Schedule or refresh everything in the window.
        for workout in window {
            await scheduleIfPermitted(workout)
        }

        preferences.lastSuccessfulSynchronization = Date()
        try? context.save()
    }

    /// Sessions eligible for the Watch: within the horizon, still planned, and
    /// not already done. A completed session must never be pushed.
    private func upcomingWindow(now: Date) -> [ScheduledWorkout] {
        guard let days = preferences.horizon.days else { return [] }
        let calendar = workoutStore.configuration?.calendar ?? .current
        let candidates = workoutStore.allWorkouts
            .filter { $0.status == .planned && $0.plannedStart >= now }
            .sorted { $0.plannedStart < $1.plannedStart }

        if preferences.horizon == .nextWorkout {
            return Array(candidates.prefix(1))
        }
        guard let end = calendar.date(byAdding: .day, value: days, to: now) else { return [] }
        return candidates.filter { $0.plannedStart <= end }
    }

    /// Schedule one session, if its conversion permits it without asking.
    private func scheduleIfPermitted(_ workout: ScheduledWorkout) async {
        let conversion = conversion(for: workout)
        guard conversion.outcome.isSchedulable else {
            persist(unsupported: conversion, for: workout)
            return
        }

        let stored = record(for: workout.id)

        // A simplification needs explicit approval of *this* fingerprint.
        if conversion.requiresUserConfirmation {
            let approved = stored?.userConfirmedSimplification == true
                && stored?.conversionFingerprint == conversion.fingerprint
            guard approved else {
                persist(awaitingApproval: conversion, for: workout)
                return
            }
        }

        // Already scheduled, unchanged, and current — nothing to do.
        if let stored,
           stored.status == .scheduled,
           stored.conversionFingerprint == conversion.fingerprint,
           stored.lastScheduledStart == workout.plannedStart,
           stored.conversionVersion == WorkoutKitConversionResult.currentVersion {
            return
        }

        // The plan moved or the conversion changed: remove the old plan first so
        // the Watch cannot keep a stale copy alongside the new one.
        if let stored, stored.status == .scheduled {
            await remove(scheduledWorkoutID: workout.id, keepRecord: true)
        }

        await performSchedule(conversion, for: workout)
    }

    private func performSchedule(_ conversion: WorkoutKitConversionResult, for workout: ScheduledWorkout) async {
        let request = WorkoutKitScheduleRequest(
            workoutPlanID: conversion.deterministicWorkoutPlanID,
            scheduledWorkoutID: workout.id,
            plannedStart: workout.plannedStart,
            conversion: conversion)

        persist(scheduling: conversion, for: workout, request: request)

        do {
            try await scheduler.schedule(request)
            persist(scheduled: conversion, for: workout, request: request)
        } catch let error as WorkoutKitSchedulingError {
            persist(failure: error.category, for: workout.id)
        } catch {
            persist(failure: .scheduleFailed, for: workout.id)
        }
    }

    /// Approve a simplification, then schedule it.
    func approveSimplification(for workout: ScheduledWorkout) async {
        let conversion = conversion(for: workout)
        guard conversion.outcome == .simplified else { return }

        var record = self.record(for: workout.id) ?? newRecord(conversion, for: workout, identifier: conversion.deterministicWorkoutPlanID.uuidString)
        record.userConfirmedSimplification = true
        record.conversionFingerprint = conversion.fingerprint
        record.status = .scheduling
        persist(record)
        try? context.save()

        await performSchedule(conversion, for: workout)
    }

    // MARK: - Removal and reconciliation

    func remove(scheduledWorkoutID: UUID, keepRecord: Bool = false) async {
        guard let stored = record(for: scheduledWorkoutID) else { return }
        guard let workout = workoutStore.workout(id: scheduledWorkoutID) else { return }

        let request = WorkoutKitScheduleRequest(
            workoutPlanID: UUID(uuidString: stored.schedulingIdentifier) ?? conversion(for: workout).deterministicWorkoutPlanID,
            scheduledWorkoutID: scheduledWorkoutID,
            plannedStart: stored.lastScheduledStart,
            conversion: conversion(for: workout))

        do {
            try await scheduler.remove(request)
            var updated = stored
            updated.status = keepRecord ? .rescheduling : .removed
            updated.removedAt = keepRecord ? nil : Date()
            updated.lastSynchronization = Date()
            persist(updated)
        } catch {
            persist(failure: .removalFailed, for: scheduledWorkoutID)
        }
        try? context.save()
    }

    /// Called after any plan mutation (§I). A session that is finished, skipped,
    /// replaced or moved must not leave a stale workout on the Watch.
    func reconcileAfterPlanChange(scheduledWorkoutID: UUID) async {
        guard preferences.isEnabled, scheduler.isSupported else { return }
        guard let workout = workoutStore.workout(id: scheduledWorkoutID) else {
            await remove(scheduledWorkoutID: scheduledWorkoutID)
            return
        }
        if workout.status != .planned {
            await remove(scheduledWorkoutID: scheduledWorkoutID)
            return
        }
        await scheduleIfPermitted(workout)
        try? context.save()
    }

    func removeAllScheduled() async {
        do {
            try await scheduler.removeAllEndurancePlans()
            for row in rows() {
                if var domain = try? row.toDomain() {
                    domain.status = .removed
                    domain.removedAt = Date()
                    try? row.update(domain)
                }
            }
            try context.save()
        } catch {
            lastFailure = .removalFailed
        }
    }

    /// Reconcile against the system's own schedule, recovering a framework call
    /// that succeeded while our local transaction did not finish.
    func reconcileWithSystem() async {
        guard scheduler.isSupported, preferences.isEnabled else { return }
        guard let plans = try? await scheduler.scheduledPlans() else { return }
        let live = Set(plans.map(\.workoutPlanID.uuidString))

        for row in rows() {
            guard var domain = try? row.toDomain() else { continue }
            let isLive = live.contains(domain.schedulingIdentifier)
            if domain.status == .scheduling && isLive {
                // The framework accepted it; our record never caught up.
                domain.status = .scheduled
                domain.lastSynchronization = Date()
                try? row.update(domain)
            } else if domain.status == .scheduled && !isLive {
                domain.status = .removed
                domain.removedAt = Date()
                try? row.update(domain)
            }
        }
        try? context.save()
    }

    // MARK: - Persistence

    private func rows() -> [SDWorkoutKitScheduleRecord] {
        (try? context.fetch(FetchDescriptor<SDWorkoutKitScheduleRecord>())) ?? []
    }

    private func newRecord(
        _ conversion: WorkoutKitConversionResult,
        for workout: ScheduledWorkout,
        identifier: String
    ) -> WorkoutKitScheduleRecord {
        WorkoutKitScheduleRecord(
            scheduledWorkoutID: workout.id,
            schedulingIdentifier: identifier,
            templateID: conversion.templateID,
            conversionOutcome: conversion.outcome,
            conversionVersion: conversion.conversionVersion,
            conversionFingerprint: conversion.fingerprint,
            originalPlannedStart: workout.plannedStart,
            lastScheduledStart: workout.plannedStart,
            status: .notEvaluated,
            warnings: conversion.warnings)
    }

    private func persist(unsupported conversion: WorkoutKitConversionResult, for workout: ScheduledWorkout) {
        var record = self.record(for: workout.id)
            ?? newRecord(conversion, for: workout, identifier: conversion.deterministicWorkoutPlanID.uuidString)
        record.status = .unsupported
        record.conversionOutcome = .unsupported
        record.conversionFingerprint = conversion.fingerprint
        record.warnings = conversion.warnings
        persist(record)
    }

    private func persist(awaitingApproval conversion: WorkoutKitConversionResult, for workout: ScheduledWorkout) {
        var record = self.record(for: workout.id)
            ?? newRecord(conversion, for: workout, identifier: conversion.deterministicWorkoutPlanID.uuidString)
        record.status = .simplifiedAvailable
        record.conversionOutcome = .simplified
        // A different simplification invalidates any previous approval.
        if record.conversionFingerprint != conversion.fingerprint {
            record.userConfirmedSimplification = false
            record.conversionFingerprint = conversion.fingerprint
        }
        record.warnings = conversion.warnings
        persist(record)
    }

    private func persist(
        scheduling conversion: WorkoutKitConversionResult,
        for workout: ScheduledWorkout,
        request: WorkoutKitScheduleRequest
    ) {
        var record = self.record(for: workout.id)
            ?? newRecord(conversion, for: workout, identifier: request.workoutPlanID.uuidString)
        record.schedulingIdentifier = request.workoutPlanID.uuidString
        record.status = .scheduling
        record.conversionOutcome = conversion.outcome
        record.conversionVersion = conversion.conversionVersion
        record.conversionFingerprint = conversion.fingerprint
        record.lastScheduledStart = workout.plannedStart
        record.warnings = conversion.warnings
        persist(record)
        // Written before the framework call, so a call that succeeds while the
        // app dies is recoverable by `reconcileWithSystem` (§I).
        try? context.save()
    }

    private func persist(
        scheduled conversion: WorkoutKitConversionResult,
        for workout: ScheduledWorkout,
        request: WorkoutKitScheduleRequest
    ) {
        var record = self.record(for: workout.id)
            ?? newRecord(conversion, for: workout, identifier: request.workoutPlanID.uuidString)
        record.status = .scheduled
        record.lastSynchronization = Date()
        record.lastFailure = nil
        record.retryCount = 0
        record.removedAt = nil
        persist(record)
        lastFailure = nil
    }

    private func persist(failure category: WorkoutKitFailureCategory, for scheduledWorkoutID: UUID) {
        guard var record = self.record(for: scheduledWorkoutID) else {
            lastFailure = category
            return
        }
        record.lastFailure = category
        record.retryCount += 1
        record.status = category.classification == .retryable ? .failedRetryable : .failedPermanent
        persist(record)
        lastFailure = category
        // Stable code only — never framework text (§P, §Q).
        AppLog.app.error("WorkoutKit scheduling failed: \(category.rawValue, privacy: .public)")
    }

    private func persist(_ record: WorkoutKitScheduleRecord) {
        if let existing = rows().first(where: { $0.scheduledWorkoutID == record.scheduledWorkoutID }) {
            try? existing.update(record)
        } else if let inserted = try? SDWorkoutKitScheduleRecord(domain: record) {
            context.insert(inserted)
        }
    }
}
