import Foundation

/// Deterministic date construction for tests. Builds instants from components in
/// an explicit time zone so DST/leap-year tests are reproducible regardless of
/// the machine's locale.
enum TestDates {
    static func gregorian(_ tzID: String) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: tzID)!
        return c
    }

    static func date(
        _ year: Int, _ month: Int, _ day: Int,
        _ hour: Int = 0, _ minute: Int = 0,
        tz tzID: String = "America/New_York"
    ) -> Date {
        var comps = DateComponents()
        comps.year = year; comps.month = month; comps.day = day
        comps.hour = hour; comps.minute = minute; comps.second = 0
        return gregorian(tzID).date(from: comps)!
    }
}
