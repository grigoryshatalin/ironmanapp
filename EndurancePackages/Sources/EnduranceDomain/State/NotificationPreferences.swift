import Foundation

/// A category of local reminder. Per-category opt-in is a hard requirement
/// (§7 Step 5, §13) and also App Review 4.5.4 (notifications must be optional).
public enum NotificationCategory: String, Codable, Sendable, Hashable, CaseIterable {
    case preparation    // evening-before prep
    case workout        // at/near the session
    case secondReminder // optional follow-up
    case fueling        // long-session fueling
    case recovery       // recovery check
    case weeklyReview    // weekly review

    public var localizationKey: String { "notifcategory.\(rawValue)" }

    /// SF Symbol for the category (paired with text, never color-only).
    public var symbolName: String {
        switch self {
        case .preparation: return "bag"
        case .workout: return "bell"
        case .secondReminder: return "bell.badge"
        case .fueling: return "fork.knife"
        case .recovery: return "bed.double"
        case .weeklyReview: return "calendar.badge.clock"
        }
    }
}

/// Athlete notification choices. Every category defaults OFF; the app requests
/// system permission only after at least one is enabled (§7 Step 5).
public struct NotificationPreferences: Codable, Sendable, Hashable {
    public var enabledCategories: Set<NotificationCategory>
    /// Evening-before preparation reminder time.
    public var preparationTime: TimeOfDay
    /// How long before a workout the workout reminder fires (minutes).
    public var workoutLeadMinutes: Int
    /// Optional second reminder lead (minutes before start); nil disables it.
    public var secondReminderLeadMinutes: Int?
    /// Recovery-check time of day.
    public var recoveryTime: TimeOfDay
    /// Weekly review: weekday (1–7) and time.
    public var weeklyReviewWeekday: Int
    public var weeklyReviewTime: TimeOfDay
    /// Rolling scheduling window in days. The planner never schedules beyond
    /// this, and always respects the system's 64-request ceiling (§13, research
    /// confirmed the hard cap).
    public var schedulingWindowDays: Int

    public init(
        enabledCategories: Set<NotificationCategory> = [],
        preparationTime: TimeOfDay = TimeOfDay(hour: 20, minute: 0),
        workoutLeadMinutes: Int = 60,
        secondReminderLeadMinutes: Int? = nil,
        recoveryTime: TimeOfDay = TimeOfDay(hour: 21, minute: 0),
        weeklyReviewWeekday: Int = 1, // Sunday
        weeklyReviewTime: TimeOfDay = TimeOfDay(hour: 19, minute: 0),
        schedulingWindowDays: Int = 21
    ) {
        self.enabledCategories = enabledCategories
        self.preparationTime = preparationTime
        self.workoutLeadMinutes = workoutLeadMinutes
        self.secondReminderLeadMinutes = secondReminderLeadMinutes
        self.recoveryTime = recoveryTime
        self.weeklyReviewWeekday = weeklyReviewWeekday
        self.weeklyReviewTime = weeklyReviewTime
        self.schedulingWindowDays = schedulingWindowDays
    }

    public func isEnabled(_ category: NotificationCategory) -> Bool {
        enabledCategories.contains(category)
    }
}
