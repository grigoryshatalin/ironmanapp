import Foundation
import UserNotifications
import EnduranceDomain

/// Bridges the pure, tested `NotificationPlanner` to `UNUserNotificationCenter`.
/// All *decisions* (which reminders exist, their stable ids, the rolling ≤64
/// window) live in the domain and are unit-tested; this class only performs the
/// side effects and handles taps.
final class NotificationScheduler: NSObject, UNUserNotificationCenterDelegate {
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

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let userInfo = response.notification.request.content.userInfo
        if let path = userInfo["deepLink"] as? String, let link = DeepLink(path: path) {
            let handler = deepLinkHandler
            await MainActor.run { handler?(link) }
        }
    }
}
