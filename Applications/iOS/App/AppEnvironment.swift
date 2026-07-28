import SwiftUI
import SwiftData
import Observation
import EnduranceDomain
import EnduranceHealth
import EnduranceWorkoutKit

/// The four primary tabs.
enum AppTab: Hashable { case today, plan, progress, settings }

/// Composition root / dependency container. Owns the store and services and
/// mediates deep-link routing. `@Observable` so SwiftUI views update when the
/// selected tab or a pending navigation changes.
@MainActor
@Observable
final class AppEnvironment {
    let store: WorkoutStore
    let notifications: NotificationScheduler
    let snapshotWriter: SnapshotWriter
    /// Release 2 HealthKit integration. Optional at the boundary — the whole
    /// training plan works with Health unavailable or denied (§C).
    let health: HealthCoordinator
    let healthExport: HealthExportCoordinator
    /// Release 2 WorkoutKit scheduling. Off by default (§I).
    let workoutKit: WorkoutKitCoordinator
    let activeWorkout: ActiveWorkoutCoordinator

    /// Routing state driven by notification deep links.
    var selectedTab: AppTab = .today
    var pendingWorkoutID: UUID?
    var pendingReviewWeek: Int?

    /// A user-facing, recoverable error (never a raw system error string).
    var alert: AppAlert?

    init(
        modelContainer: ModelContainer,
        healthImporter: (any HealthWorkoutImporting)? = nil,
        healthExporter: (any HealthExporting)? = nil,
        workoutScheduler: (any WorkoutScheduling)? = nil,
        activeWorkoutSession: (any ActiveWorkoutManaging)? = nil
    ) {
        let store = WorkoutStore(modelContainer: modelContainer)
        self.store = store
        self.notifications = NotificationScheduler()
        self.snapshotWriter = SnapshotWriter(appGroupID: AppConfig.appGroupIdentifier)
        // Injectable so tests and previews drive a deterministic importer rather
        // than the real HealthKit store (§T).
        self.health = HealthCoordinator(
            importer: healthImporter ?? HealthCoordinator.defaultImporter(),
            container: modelContainer,
            workoutStore: store)
        self.healthExport = HealthExportCoordinator(
            exporter: healthExporter ?? HealthExportCoordinator.defaultExporter(),
            container: modelContainer)
        self.activeWorkout = ActiveWorkoutCoordinator(
            session: activeWorkoutSession ?? PhoneWorkoutSession(),
            container: modelContainer,
            workoutStore: store)
        self.workoutKit = WorkoutKitCoordinator(
            scheduler: workoutScheduler ?? WorkoutKitCoordinator.defaultScheduler(),
            container: modelContainer,
            workoutStore: store)
    }

    /// Called once when the UI appears.
    func start() async {
        notifications.registerCategories()
        notifications.deepLinkHandler = { [weak self] link in
            Task { @MainActor in self?.route(link) }
        }
        do {
            try store.load()
        } catch {
            AppLog.persistence.error("Load failed: \(error)")
            alert = .dataError
        }
        // Restore persisted integration toggles BEFORE anything reads them:
        // import and rescan both guard on `isImportEnabled`.
        // A session that was live when the app died is the athlete's work, and
        // they are owed a decision about it rather than silent deletion (§G).
        activeWorkout.checkForInterruptedSession()
        health.restorePreferences()
        await health.refreshConnectionState()
        healthExport.restorePreferences()
        workoutKit.restorePreferences()
        healthExport.refreshAuthorization()
        // An export interrupted between HealthKit's save and our persistence
        // must be reconnected, not left as an invisible orphan (§9).
        await healthExport.recoverOrphanedExports()
        await workoutKit.refreshAuthorization()
        // A scheduling call the framework accepted while the app died must be
        // reconciled, not left diverged (§I).
        await workoutKit.reconcileWithSystem()
        await refreshSideEffects()
    }

    /// Re-derive notifications and the shared snapshot from current state. Safe to
    /// call after any mutation; idempotent.
    func refreshSideEffects() async {
        guard store.isConfigured else { return }
        await notifications.sync(
            workouts: store.allWorkouts,
            preferences: store.notificationPreferences,
            calendar: store.configuration?.calendar ?? .current
        )
        snapshotWriter.write(store.todaySnapshot())
    }

    /// Complete a session and, only afterwards, consider exporting it (§5).
    ///
    /// Ordering is deliberate and load-bearing: the local completion is
    /// persisted first and is never rolled back by a HealthKit failure. Training
    /// history belongs to the athlete, not to whether a system framework
    /// accepted a write.
    func completeWorkout(_ workout: ScheduledWorkout, completion: WorkoutCompletion) async throws {
        try store.complete(workout.id, completion: completion)

        // Record the execution — the identity everything else de-duplicates on.
        let execution = WorkoutExecution(
            scheduledWorkoutID: workout.id,
            source: completion.source,
            start: completion.completedAt.addingTimeInterval(
                -Double((completion.actualDurationMinutes ?? workout.effectivePlannedMinutes) * 60)),
            durationSeconds: (completion.actualDurationMinutes ?? workout.effectivePlannedMinutes) * 60,
            distanceMeters: completion.actualDistanceMeters,
            averageHeartRate: completion.averageHeartRate)
        store.recordExecution(execution)

        notifications.cancel(for: workout.id)
        // A completed session must not stay scheduled on the Watch (§I).
        await workoutKit.reconcileAfterPlanChange(scheduledWorkoutID: workout.id)
        await refreshSideEffects()

        // Non-blocking: a failure here leaves a retryable state, not a lost session.
        await healthExport.exportIfAutomatic(execution: execution, sport: workout.sport)
    }

    /// Route a deep link like `endurance://workout/<uuid>` or `.../review/<week>`.
    func route(_ link: DeepLink) {
        switch link {
        case .today:
            selectedTab = .today
        case .workout(let id):
            selectedTab = .today
            pendingWorkoutID = id
        case .review(let week):
            selectedTab = .plan
            pendingReviewWeek = week
        }
    }
}

/// Calm, recoverable alerts — mapped to native `.alert` presentations.
enum AppAlert: Identifiable {
    case dataError
    case exportFailed
    var id: String { String(describing: self) }
}
