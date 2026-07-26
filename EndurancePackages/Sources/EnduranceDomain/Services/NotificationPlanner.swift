import Foundation

/// System-independent description of a local notification to schedule. The app
/// layer converts this into a `UNNotificationRequest`; keeping it as data makes
/// generation/cancellation logic fully unit-testable (§13).
public struct PlannedNotification: Sendable, Hashable, Identifiable {
    public enum InterruptionLevel: String, Sendable, Hashable { case passive, active, timeSensitive }

    /// Stable, derivable identifier (never random) so it can be cancelled and
    /// deduplicated precisely.
    public var id: String
    public var category: NotificationCategory
    public var workoutID: UUID?
    public var weekNumber: Int?
    public var fireDate: Date
    public var title: String
    public var body: String
    /// Groups related notifications in Notification Center.
    public var threadIdentifier: String
    /// Deep-link path the tap handler routes on, e.g. "workout/<uuid>".
    public var deepLinkPath: String
    public var interruptionLevel: InterruptionLevel

    public init(
        id: String,
        category: NotificationCategory,
        workoutID: UUID?,
        weekNumber: Int?,
        fireDate: Date,
        title: String,
        body: String,
        threadIdentifier: String,
        deepLinkPath: String,
        interruptionLevel: InterruptionLevel
    ) {
        self.id = id
        self.category = category
        self.workoutID = workoutID
        self.weekNumber = weekNumber
        self.fireDate = fireDate
        self.title = title
        self.body = body
        self.threadIdentifier = threadIdentifier
        self.deepLinkPath = deepLinkPath
        self.interruptionLevel = interruptionLevel
    }
}

/// Builds the set of notifications that *should* currently be scheduled, given
/// the plan schedule and the athlete's preferences.
///
/// Two hard constraints from research drive the design:
///   1. iOS keeps at most **64** pending requests; excess is silently dropped.
///      So we schedule only a rolling window and cap at a budget ≤ 64.
///   2. Identifiers must be **stable/derivable** so completing or moving a
///      workout can cancel exactly the right requests.
///
/// The planner is pure: it returns the desired set and the identifiers to
/// cancel for a workout. The app diffs this against what's actually pending.
public struct NotificationPlanner: Sendable {

    /// Hard system ceiling. We never exceed this regardless of preferences.
    public static let systemPendingLimit = 64

    public var maxScheduled: Int

    public init(maxScheduled: Int = NotificationPlanner.systemPendingLimit) {
        self.maxScheduled = min(maxScheduled, Self.systemPendingLimit)
    }

    public struct Plan: Sendable, Hashable {
        /// The notifications to schedule, soonest first, within budget.
        public var toSchedule: [PlannedNotification]
        /// How many candidate notifications fell outside the window/budget.
        public var droppedCount: Int
    }

    // MARK: - Identifier scheme (stable & derivable)

    public static func workoutIdentifier(_ workoutID: UUID) -> String { "workout.\(workoutID.uuidString)" }
    public static func preparationIdentifier(_ workoutID: UUID) -> String { "preparation.\(workoutID.uuidString)" }
    public static func fuelingIdentifier(_ workoutID: UUID) -> String { "fueling.\(workoutID.uuidString)" }
    public static func secondIdentifier(_ workoutID: UUID) -> String { "second.\(workoutID.uuidString)" }
    public static func recoveryIdentifier(dayIndex: Int) -> String { "recovery.day.\(dayIndex)" }
    public static func weeklyReviewIdentifier(week: Int) -> String { "weeklyReview.\(week)" }

    /// Every identifier that could belong to a given workout — used to cancel
    /// all of its pending reminders on completion/skip/replace (§8, §13).
    public static func allIdentifiers(for workoutID: UUID) -> [String] {
        [workoutIdentifier(workoutID), preparationIdentifier(workoutID),
         fuelingIdentifier(workoutID), secondIdentifier(workoutID)]
    }

    // MARK: - Generation

    /// Build the desired schedule.
    ///
    /// - Parameters:
    ///   - workouts: current scheduled workouts (any statuses).
    ///   - preferences: category toggles and timings.
    ///   - now: the reference "now".
    ///   - calendar: calendar/time-zone to resolve wall-clock fire times.
    public func plan(
        workouts: [ScheduledWorkout],
        preferences: NotificationPreferences,
        now: Date,
        calendar: Calendar
    ) -> Plan {
        let windowEnd = calendar.date(byAdding: .day, value: preferences.schedulingWindowDays, to: now) ?? now
        var candidates: [PlannedNotification] = []

        // Only planned/in-progress, non-completed sessions get reminders.
        let active = workouts.filter { $0.status == .planned || $0.status == .inProgress }

        for w in active {
            candidates.append(contentsOf: workoutNotifications(for: w, preferences: preferences, calendar: calendar))
        }

        // Recovery checks: one per day that contains a hard/long session.
        if preferences.isEnabled(.recovery) {
            candidates.append(contentsOf: recoveryNotifications(active, preferences: preferences, calendar: calendar))
        }

        // Weekly review: one per week present in the schedule.
        if preferences.isEnabled(.weeklyReview) {
            candidates.append(contentsOf: weeklyReviewNotifications(workouts, preferences: preferences, calendar: calendar))
        }

        // Keep only future, in-window; dedupe by id (stable); sort soonest-first.
        var seen = Set<String>()
        let windowed = candidates
            .filter { $0.fireDate > now && $0.fireDate <= windowEnd }
            .sorted { $0.fireDate < $1.fireDate }
            .filter { seen.insert($0.id).inserted }

        let kept = Array(windowed.prefix(maxScheduled))
        return Plan(toSchedule: kept, droppedCount: windowed.count - kept.count)
    }

    // MARK: - Builders

    private func workoutNotifications(
        for w: ScheduledWorkout,
        preferences: NotificationPreferences,
        calendar: Calendar
    ) -> [PlannedNotification] {
        var out: [PlannedNotification] = []
        let thread = "workout.\(w.id.uuidString)"
        let deepLink = "workout/\(w.id.uuidString)"
        let zone = w.intensity.zoneShorthand.map { "\($0) · " } ?? ""

        // Workout reminder.
        if preferences.isEnabled(.workout),
           let fire = calendar.date(byAdding: .minute, value: -preferences.workoutLeadMinutes, to: w.plannedStart) {
            out.append(.init(
                id: Self.workoutIdentifier(w.id), category: .workout, workoutID: w.id, weekNumber: w.weekNumber,
                fireDate: fire, title: w.title,
                body: "\(zone)\(w.objective)", threadIdentifier: thread, deepLinkPath: deepLink,
                interruptionLevel: .active))
        }

        // Optional second reminder.
        if preferences.isEnabled(.secondReminder), let lead = preferences.secondReminderLeadMinutes,
           let fire = calendar.date(byAdding: .minute, value: -lead, to: w.plannedStart) {
            out.append(.init(
                id: Self.secondIdentifier(w.id), category: .secondReminder, workoutID: w.id, weekNumber: w.weekNumber,
                fireDate: fire, title: "Soon: \(w.title)",
                body: w.objective, threadIdentifier: thread, deepLinkPath: deepLink, interruptionLevel: .active))
        }

        // Evening-before preparation, for sessions worth prepping (long/brick/race).
        let needsPrep = w.stressCategory == .long || w.stressCategory == .raceSpecific || w.isBrick || w.sport == .race
        if preferences.isEnabled(.preparation), needsPrep,
           let dayBefore = calendar.date(byAdding: .day, value: -1, to: w.scheduledDate),
           let fire = calendar.date(bySettingHour: preferences.preparationTime.hour, minute: preferences.preparationTime.minute, second: 0, of: dayBefore) {
            out.append(.init(
                id: Self.preparationIdentifier(w.id), category: .preparation, workoutID: w.id, weekNumber: w.weekNumber,
                fireDate: fire, title: "Prepare for tomorrow’s \(w.sport.englishName.lowercased())",
                body: "Lay out gear and plan your route for “\(w.title)”.",
                threadIdentifier: thread, deepLinkPath: deepLink, interruptionLevel: .passive))
        }

        // Fueling, for long/race-specific sessions.
        let needsFuel = w.stressCategory == .long || w.stressCategory == .raceSpecific
        if preferences.isEnabled(.fueling), needsFuel,
           let fire = calendar.date(byAdding: .minute, value: -90, to: w.plannedStart) {
            out.append(.init(
                id: Self.fuelingIdentifier(w.id), category: .fueling, workoutID: w.id, weekNumber: w.weekNumber,
                fireDate: fire, title: "Fuel the long session",
                body: "Bring enough carbohydrate and fluid for the planned duration, and practice your race-day fueling.",
                threadIdentifier: thread, deepLinkPath: deepLink, interruptionLevel: .passive))
        }

        return out
    }

    private func recoveryNotifications(
        _ active: [ScheduledWorkout],
        preferences: NotificationPreferences,
        calendar: Calendar
    ) -> [PlannedNotification] {
        // Group by day; one recovery check per day that has a high-stress session.
        let byDay = Dictionary(grouping: active, by: { $0.dayIndex })
        var out: [PlannedNotification] = []
        for (dayIndex, sessions) in byDay {
            guard sessions.contains(where: { $0.stressCategory.isHighStress }) else { continue }
            guard let anchor = sessions.first?.scheduledDate,
                  let fire = calendar.date(bySettingHour: preferences.recoveryTime.hour, minute: preferences.recoveryTime.minute, second: 0, of: anchor)
            else { continue }
            out.append(.init(
                id: Self.recoveryIdentifier(dayIndex: dayIndex), category: .recovery, workoutID: nil,
                weekNumber: sessions.first?.weekNumber, fireDate: fire, title: "Recovery check",
                body: "Log how you feel and prepare for tomorrow.",
                threadIdentifier: "recovery", deepLinkPath: "today", interruptionLevel: .passive))
        }
        return out
    }

    private func weeklyReviewNotifications(
        _ workouts: [ScheduledWorkout],
        preferences: NotificationPreferences,
        calendar: Calendar
    ) -> [PlannedNotification] {
        let byWeek = Dictionary(grouping: workouts, by: { $0.weekNumber })
        var out: [PlannedNotification] = []
        for (week, sessions) in byWeek {
            // Fire on the configured review weekday within the last day of the week.
            guard let lastDay = sessions.map(\.scheduledDate).max(),
                  let fire = calendar.date(bySettingHour: preferences.weeklyReviewTime.hour, minute: preferences.weeklyReviewTime.minute, second: 0, of: lastDay)
            else { continue }
            out.append(.init(
                id: Self.weeklyReviewIdentifier(week: week), category: .weeklyReview, workoutID: nil,
                weekNumber: week, fireDate: fire, title: "Review Week \(week)",
                body: "Check your completed training and preview next week.",
                threadIdentifier: "weeklyReview", deepLinkPath: "review/\(week)", interruptionLevel: .passive))
        }
        return out
    }
}
