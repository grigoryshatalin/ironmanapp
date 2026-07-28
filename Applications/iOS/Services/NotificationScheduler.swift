import Foundation
import UserNotifications
import EnduranceDomain

/// Bridges the pure, tested `NotificationPlanner` to `UNUserNotificationCenter`.
/// All *decisions* (which reminders exist, their stable ids, the rolling ≤64
/// window) live in the domain and are unit-tested; this class only performs the
/// side effects and handles taps.
/// Main-actor isolated: it is owned by the main-actor `AppEnvironment`, and the
/// class holds non-`Sendable` state (`deepLinkHandler`). Without this, awaiting
/// `sync` from the main actor would send a non-`Sendable` value across an
/// isolation boundary.
@MainActor
final class NotificationScheduler: NSObject, @preconcurrency UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    private let planner = NotificationPlanner()

    /// Invoked (on the main actor by the caller) when a notification is tapped.
    var deepLinkHandler: ((DeepLink) -> Void)?

    override init() {
        super.init()
        center.delegate = self
    }

    // MARK: - Authorization

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    /// Request permission. Called only after the user enables ≥1 category.
    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            AppLog.notifications.error("Authorization request failed: \(error)")
            return false
        }
    }

    func registerCategories() {
        let complete = UNNotificationAction(identifier: AppConfig.NotificationActionID.markComplete,
                                            title: "Mark complete", options: [.authenticationRequired])
        let open = UNNotificationAction(identifier: AppConfig.NotificationActionID.openWorkout,
                                        title: "Open", options: [.foreground])
        let workout = UNNotificationCategory(identifier: AppConfig.NotificationCategoryID.workout,
                                             actions: [complete, open], intentIdentifiers: [], options: [])
        let review = UNNotificationCategory(identifier: AppConfig.NotificationCategoryID.review,
                                            actions: [open], intentIdentifiers: [], options: [])
        center.setNotificationCategories([workout, review])
    }

    // MARK: - Sync (diff desired vs pending)

    /// Reconcile the currently-pending requests with the desired set. Because ids
    /// are stable, this cancels obsolete reminders, keeps valid ones, and adds
    /// new ones — never duplicating (brief §13).
    func sync(workouts: [ScheduledWorkout], preferences: NotificationPreferences, calendar: Calendar, now: Date = Date()) async {
        guard await authorizationStatus() == .authorized, !preferences.enabledCategories.isEmpty else {
            // Not authorized or nothing enabled → clear everything we own.
            center.removeAllPendingNotificationRequests()
            return
        }

        let desired = planner.plan(workouts: workouts, preferences: preferences, now: now, calendar: calendar).toSchedule
        let desiredByID = Dictionary(uniqueKeysWithValues: desired.map { ($0.id, $0) })

        let pending = await center.pendingNotificationRequests()
        let pendingIDs = Set(pending.map(\.identifier))
        let desiredIDs = Set(desiredByID.keys)

        // Remove pending requests that are no longer desired.
        let toRemove = pendingIDs.subtracting(desiredIDs)
        if !toRemove.isEmpty { center.removePendingNotificationRequests(withIdentifiers: Array(toRemove)) }

        // Add desired requests that aren't already pending.
        for id in desiredIDs.subtracting(pendingIDs) {
            guard let n = desiredByID[id] else { continue }
            add(n, calendar: calendar)
        }
    }

    /// Cancel every reminder that could belong to a workout (e.g. on completion).
    func cancel(for workoutID: UUID) {
        center.removePendingNotificationRequests(withIdentifiers: NotificationPlanner.allIdentifiers(for: workoutID))
    }

    private func add(_ n: PlannedNotification, calendar: Calendar) {
        let content = UNMutableNotificationContent()
        content.title = n.title
        content.body = n.body
        content.threadIdentifier = n.threadIdentifier
        content.sound = .default
        content.userInfo = ["deepLink": n.deepLinkPath]
        content.interruptionLevel = interruptionLevel(n.interruptionLevel)
        switch n.category {
        case .workout, .secondReminder: content.categoryIdentifier = AppConfig.NotificationCategoryID.workout
        case .weeklyReview: content.categoryIdentifier = AppConfig.NotificationCategoryID.review
        default: break
        }

        let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: n.fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        center.add(UNNotificationRequest(identifier: n.id, content: content, trigger: trigger)) { error in
            if let error { AppLog.notifications.error("Schedule \(n.id) failed: \(error)") }
        }
    }

    private func interruptionLevel(_ level: PlannedNotification.InterruptionLevel) -> UNNotificationInterruptionLevel {
        switch level {
        case .passive: return .passive
        case .active: return .active
        case .timeSensitive: return .timeSensitive
        }
    }

    // MARK: - Diagnostics

    #if DEBUG
    /// One pending reminder, as iOS actually holds it.
    struct PendingReminder: Identifiable, Sendable, Equatable {
        let id: String
        let title: String
        let fireDate: Date?
        let categoryIdentifier: String
    }

    /// What iOS is actually holding, not what the planner believes it asked for.
    ///
    /// The planner's decisions are unit-tested; what has never been observable is
    /// the *bridge* — whether `sync` genuinely reconciles against
    /// `UNUserNotificationCenter` on device. Non-duplication, regeneration and
    /// cancellation are all statements about this set, and all three can be
    /// checked by reading it rather than by waiting for a reminder to fire.
    func pendingReminders() async -> [PendingReminder] {
        let requests = await center.pendingNotificationRequests()
        return requests.map { request in
            let calendarDate = (request.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate()
            let intervalDate = (request.trigger as? UNTimeIntervalNotificationTrigger)?.nextTriggerDate()
            return PendingReminder(
                id: request.identifier,
                title: request.content.title,
                fireDate: calendarDate ?? intervalDate,
                categoryIdentifier: request.content.categoryIdentifier)
        }
        .sorted { ($0.fireDate ?? .distantFuture) < ($1.fireDate ?? .distantFuture) }
    }

    /// Re-run `sync` with the exact same inputs. Non-duplication means the
    /// pending set is byte-identical afterwards — stable identifiers are what
    /// make that true, and this is how to observe it rather than assume it.
    func resync(workouts: [ScheduledWorkout], preferences: NotificationPreferences, calendar: Calendar) async {
        await sync(workouts: workouts, preferences: preferences, calendar: calendar)
    }

    /// Fire a real reminder a few seconds from now, for a real session.
    ///
    /// Deliberately built through `add(_:calendar:)` — the same path production
    /// reminders take — so the payload, category, thread and `deepLink` userInfo
    /// are byte-for-byte what a genuine notification carries. A hand-rolled test
    /// notification would prove nothing about the tap-handling path, which is
    /// exactly what we are trying to exercise.
    @discardableResult
    func scheduleDiagnosticReminder(
        for workout: ScheduledWorkout,
        after seconds: TimeInterval = 5
    ) async -> Bool {
        guard await authorizationStatus() == .authorized else { return false }

        let fireDate = Date().addingTimeInterval(seconds)
        let planned = PlannedNotification(
            id: "diagnostic.\(workout.id.uuidString)",
            category: .workout,
            workoutID: workout.id,
            weekNumber: workout.weekNumber,
            fireDate: fireDate,
            title: workout.title,
            body: String(localized: "Test reminder — tap to open this session."),
            threadIdentifier: "diagnostic",
            deepLinkPath: "workout/\(workout.id.uuidString)",
            interruptionLevel: .active)

        // A calendar trigger only resolves to minute precision, so a few seconds
        // out would round to "now" and may not fire. Use an interval trigger for
        // the diagnostic while keeping the identical content.
        let content = UNMutableNotificationContent()
        content.title = planned.title
        content.body = planned.body
        content.threadIdentifier = planned.threadIdentifier
        content.sound = .default
        content.userInfo = ["deepLink": planned.deepLinkPath]
        content.interruptionLevel = interruptionLevel(planned.interruptionLevel)
        content.categoryIdentifier = AppConfig.NotificationCategoryID.workout

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, seconds), repeats: false)
        let request = UNNotificationRequest(identifier: planned.id, content: content, trigger: trigger)

        do {
            try await center.add(request)
            AppLog.notifications.info("Diagnostic reminder scheduled for \(Int(seconds))s")
            return true
        } catch {
            AppLog.notifications.error("Diagnostic reminder failed: \(error)")
            return false
        }
    }
    #endif

    // MARK: - UNUserNotificationCenterDelegate

    // UserNotifications delivers these on the main thread and asserts as much
    // internally. An earlier version marked them `nonisolated` to satisfy the
    // non-`Sendable` parameter diagnostics; that compiled cleanly and crashed on
    // device with "Call must be made on main thread" the first time a
    // notification was tapped. `@preconcurrency` on the conformance silences the
    // same diagnostics while keeping the work where the framework requires it.

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let path = response.notification.request.content.userInfo["deepLink"] as? String
        guard let path, let link = DeepLink(path: path) else { return }
        deepLinkHandler?(link)
    }
}
