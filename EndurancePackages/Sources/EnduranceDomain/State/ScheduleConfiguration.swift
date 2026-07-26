import Foundation

/// A local time-of-day, stored as components (never absolute seconds) so it
/// survives DST transitions unchanged (§17).
public struct TimeOfDay: Codable, Sendable, Hashable {
    public var hour: Int
    public var minute: Int

    public init(hour: Int, minute: Int) {
        self.hour = hour
        self.minute = minute
    }

    public static let defaultWeekday = TimeOfDay(hour: 6, minute: 30)
    public static let defaultWeekend = TimeOfDay(hour: 8, minute: 0)
}

/// The single source of truth for the plan's calendar mapping. Either the start
/// date or the race date is authoritative; the engine derives the other (§17).
public enum PlanAnchor: Codable, Sendable, Hashable {
    case startDate(Date)
    case raceDate(Date)
}

/// Everything `ScheduleEngine` needs to turn plan day-indices into real dates
/// and start times. Deliberately narrow — the full app settings live in the app
/// layer and reference this.
public struct ScheduleConfiguration: Codable, Sendable, Hashable {
    public var anchor: PlanAnchor
    /// Gregorian weekday the plan's weeks begin on (1 = Sun … 7 = Sat). Mirrors
    /// the plan's `startWeekday`; kept here so the engine is self-contained.
    public var startWeekday: Int
    public var weekdayDefaultTime: TimeOfDay
    public var weekendDefaultTime: TimeOfDay
    /// IANA time-zone identifier; nil means "use the device's current zone".
    public var timeZoneIdentifier: String?

    // Preferred long-session / rest days (Gregorian weekday ints). Recorded now;
    // the day-rotation transform that applies them ships incrementally. Keeping
    // them here means enabling the feature later needs no schema change.
    public var preferredLongBikeWeekday: Int?
    public var preferredLongRunWeekday: Int?
    public var preferredRestWeekday: Int?

    public init(
        anchor: PlanAnchor,
        startWeekday: Int = 2,
        weekdayDefaultTime: TimeOfDay = .defaultWeekday,
        weekendDefaultTime: TimeOfDay = .defaultWeekend,
        timeZoneIdentifier: String? = nil,
        preferredLongBikeWeekday: Int? = nil,
        preferredLongRunWeekday: Int? = nil,
        preferredRestWeekday: Int? = nil
    ) {
        self.anchor = anchor
        self.startWeekday = startWeekday
        self.weekdayDefaultTime = weekdayDefaultTime
        self.weekendDefaultTime = weekendDefaultTime
        self.timeZoneIdentifier = timeZoneIdentifier
        self.preferredLongBikeWeekday = preferredLongBikeWeekday
        self.preferredLongRunWeekday = preferredLongRunWeekday
        self.preferredRestWeekday = preferredRestWeekday
    }

    /// A Gregorian calendar bound to the configured time zone (or current).
    public var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        if let id = timeZoneIdentifier, let tz = TimeZone(identifier: id) {
            cal.timeZone = tz
        }
        return cal
    }
}
