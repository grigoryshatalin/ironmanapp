import SwiftUI
import SwiftData
import Observation
import EnduranceDomain

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

    /// Routing state driven by notification deep links.
    var selectedTab: AppTab = .today
    var pendingWorkoutID: UUID?
    var pendingReviewWeek: Int?

    /// A user-facing, recoverable error (never a raw system error string).
    var alert: AppAlert?

    init(modelContainer: ModelContainer) {
        let store = WorkoutStore(modelContainer: modelContainer)
        self.store = store
        self.notifications = NotificationScheduler()
        self.snapshotWriter = SnapshotWriter(appGroupID: AppConfig.appGroupIdentifier)
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
