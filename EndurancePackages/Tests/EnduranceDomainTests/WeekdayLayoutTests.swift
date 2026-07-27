import Testing
import Foundation
@testable import EnduranceDomain
@testable import EnduranceTrainingPlans

/// The athlete's preferred long-ride / long-run / rest days must actually move
/// the schedule (§7). Onboarding may never collect a preference and ignore it.
@Suite("Preferred day layout")
struct WeekdayLayoutTests {

    private let tz = "America/New_York"

    /// 2026-03-02 is a Monday, matching the sample plan's `startWeekday` of 2.
    private var mondayStart: Date { TestDates.date(2026, 3, 2, tz: tz) }

    private func weekday(_ date: Date) -> Int {
        TestDates.gregorian(tz).component(.weekday, from: date)
    }

    private func config(
        bike: Int? = nil, run: Int? = nil, rest: Int? = nil
    ) -> ScheduleConfiguration {
        ScheduleConfiguration(
            anchor: .startDate(mondayStart),
            startWeekday: 2,
            weekdayDefaultTime: TimeOfDay(hour: 6, minute: 30),
            weekendDefaultTime: TimeOfDay(hour: 8, minute: 0),
            timeZoneIdentifier: tz,
            preferredLongBikeWeekday: bike,
            preferredLongRunWeekday: run,
            preferredRestWeekday: rest)
    }

    // MARK: - Role derivation

    @Test("Roles are derived from plan content, not hard-coded weekdays")
    func rolesDerivedFromContent() throws {
        let week = try #require(SamplePlan.plan(weeks: 3).weeks.first)
        // Sample week: Mon mobility, Sat long ride + brick, Sun long run.
        #expect(week.longRideDayOffset == 5)
        #expect(week.longRunDayOffset == 6)
        #expect(week.restDayOffset == 0)
    }

    @Test("The start weekday anchors the sanity of the fixture")
    func fixtureStartsOnMonday() {
        #expect(weekday(mondayStart) == 2)
    }

    // MARK: - The layout itself

    @Test("No preferences yields the identity layout")
    func noPreferencesIsIdentity() throws {
        let week = try #require(SamplePlan.plan(weeks: 3).weeks.first)
        let layout = WeekdayLayout.make(for: week, config: config(), planStartWeekday: 2)
        #expect(layout.isIdentity)
    }

    @Test("Swapping the long ride and long run produces a valid permutation")
    func swapLongDays() throws {
        let week = try #require(SamplePlan.plan(weeks: 3).weeks.first)
        // Long ride → Sunday (1), long run → Saturday (7), rest stays Monday (2).
        let layout = WeekdayLayout.make(for: week, config: config(bike: 1, run: 7, rest: 2), planStartWeekday: 2)
        #expect(layout.destinations == [0, 1, 2, 3, 4, 6, 5])
        #expect(Set(layout.destinations).count == 7, "must remain a permutation")
    }

    @Test("Every layout is a permutation of the seven days, for every preference combination")
    func alwaysAPermutation() throws {
        let plan = SamplePlan.plan(weeks: 3)
        for bike in 1...7 {
            for run in 1...7 {
                for rest in 1...7 {
                    for week in plan.weeks {
                        let layout = WeekdayLayout.make(for: week, config: config(bike: bike, run: run, rest: rest), planStartWeekday: 2)
                        #expect(Set(layout.destinations) == Set(0..<7),
                                "bike \(bike) run \(run) rest \(rest) week \(week.weekNumber) produced \(layout.destinations)")
                    }
                }
            }
        }
    }

    @Test("A conflicting preference is skipped rather than corrupting the week")
    func conflictingPreferencesStillValid() throws {
        let week = try #require(SamplePlan.plan(weeks: 3).weeks.first)
        // All three roles demand Saturday. Only the highest priority (rest) wins.
        let layout = WeekdayLayout.make(for: week, config: config(bike: 7, run: 7, rest: 7), planStartWeekday: 2)
        #expect(Set(layout.destinations) == Set(0..<7))
        #expect(layout.destination(for: 0) == 5, "rest day claims Saturday first")
    }

    // MARK: - End-to-end through the engine

    @Test("The long ride actually lands on the chosen weekday")
    func longRideMovesToChosenDay() throws {
        let plan = SamplePlan.plan(weeks: 3)
        let engine = ScheduleEngine()

        // Long ride on Sunday (1), long run on Saturday (7).
        let schedule = try engine.generateSchedule(plan: plan, config: config(bike: 1, run: 7, rest: 2))

        let longRide = try #require(schedule.first { $0.title == "Long ride" && $0.weekNumber == 1 })
        let longRun = try #require(schedule.first { $0.title == "Long run" && $0.weekNumber == 1 })

        #expect(weekday(longRide.scheduledDate) == 1, "long ride should be on Sunday")
        #expect(weekday(longRun.scheduledDate) == 7, "long run should be on Saturday")
    }

    @Test("Default layout keeps the long ride on Saturday")
    func defaultLayoutUnchanged() throws {
        let plan = SamplePlan.plan(weeks: 3)
        let schedule = try ScheduleEngine().generateSchedule(plan: plan, config: config())
        let longRide = try #require(schedule.first { $0.title == "Long ride" && $0.weekNumber == 1 })
        #expect(weekday(longRide.scheduledDate) == 7)
    }

    @Test("The brick run stays with its long ride when the week is permuted")
    func brickStaysWithItsRide() throws {
        let plan = SamplePlan.plan(weeks: 3)
        let schedule = try ScheduleEngine().generateSchedule(plan: plan, config: config(bike: 1, run: 7, rest: 2))
        let cal = TestDates.gregorian(tz)

        let ride = try #require(schedule.first { $0.title == "Long ride" && $0.weekNumber == 1 })
        let brick = try #require(schedule.first { $0.title == "Brick run" && $0.weekNumber == 1 })
        #expect(cal.isDate(ride.scheduledDate, inSameDayAs: brick.scheduledDate),
                "permuting whole days must keep a brick attached to its ride")
    }

    @Test("Each week still occupies seven distinct consecutive days")
    func noDateCollisions() throws {
        let plan = SamplePlan.plan(weeks: 3)
        let schedule = try ScheduleEngine().generateSchedule(plan: plan, config: config(bike: 1, run: 7, rest: 4))
        let cal = TestDates.gregorian(tz)

        for weekNumber in 1...3 {
            let days = Set(schedule.filter { $0.weekNumber == weekNumber }
                .map { cal.startOfDay(for: $0.scheduledDate) })
            #expect(days.count == 7, "week \(weekNumber) should span 7 distinct days")
        }
        // And the whole schedule still spans exactly the plan's day count.
        let allDays = Set(schedule.map { cal.startOfDay(for: $0.scheduledDate) })
        #expect(allDays.count == 21)
    }

    // MARK: - Identity stability (§28.2)

    @Test("Changing preferred days moves dates but preserves workout identity")
    func identitySurvivesPreferenceChange() throws {
        let plan = SamplePlan.plan(weeks: 3)
        let engine = ScheduleEngine()

        let before = try engine.generateSchedule(plan: plan, config: config())
        let after = try engine.generateSchedule(plan: plan, config: config(bike: 1, run: 7, rest: 2))

        #expect(Set(before.map(\.id)) == Set(after.map(\.id)),
                "ids are derived from the canonical plan day, so history survives")

        // ...but the long ride genuinely moved.
        let rideBefore = try #require(before.first { $0.title == "Long ride" && $0.weekNumber == 1 })
        let rideAfter = try #require(after.first { $0.id == rideBefore.id })
        #expect(weekday(rideBefore.scheduledDate) == 7)
        #expect(weekday(rideAfter.scheduledDate) == 1)
    }

    // MARK: - Against the real bundled plan

    @Test("The bundled 36-week plan permutes cleanly for every preference")
    func bundledPlanPermutesCleanly() throws {
        let plan = try BundledPlans.load36Week()
        let engine = ScheduleEngine()
        let cal = TestDates.gregorian(tz)

        // Sunday long ride, Saturday long run, Friday rest — a real reshuffle.
        let cfg = ScheduleConfiguration(
            anchor: .startDate(mondayStart), startWeekday: 2,
            weekdayDefaultTime: TimeOfDay(hour: 6, minute: 30),
            weekendDefaultTime: TimeOfDay(hour: 8, minute: 0),
            timeZoneIdentifier: tz,
            preferredLongBikeWeekday: 1, preferredLongRunWeekday: 7, preferredRestWeekday: 6)

        let schedule = try engine.generateSchedule(plan: plan, config: cfg)
        #expect(schedule.count == 382)

        // No day of the plan collapses onto another.
        let allDays = Set(schedule.map { cal.startOfDay(for: $0.scheduledDate) })
        #expect(allDays.count <= plan.totalDays)

        for week in plan.weeks {
            let layout = WeekdayLayout.make(for: week, config: cfg, planStartWeekday: 2)
            #expect(Set(layout.destinations) == Set(0..<7), "week \(week.weekNumber)")
        }
    }

    // MARK: - Start-weekday independence (regression)

    /// The bug this file could not see.
    ///
    /// Every other test here starts the plan on a Monday, matching the hardcoded
    /// `startWeekday: 2`. Offsets were derived from that nominal value rather
    /// than the weekday the plan actually begins on, so any non-Monday start
    /// shifted every preferred day silently. Found on a real device, not here.
    @Test("A preferred day lands on that weekday regardless of when the plan starts")
    func preferredDayHoldsForEveryStartWeekday() throws {
        let plan = SamplePlan.plan(weeks: 3)
        let engine = ScheduleEngine()
        let cal = TestDates.gregorian(tz)

        // 2026-03-01 is a Sunday; walk a full week of start dates.
        for dayOffset in 0..<7 {
            let start = TestDates.date(2026, 3, 1 + dayOffset, tz: tz)
            let startWeekday = cal.component(.weekday, from: start)

            let cfg = ScheduleConfiguration(
                anchor: .startDate(start),
                startWeekday: 2, // deliberately left at onboarding's hardcoded Monday
                weekdayDefaultTime: TimeOfDay(hour: 6, minute: 30),
                weekendDefaultTime: TimeOfDay(hour: 8, minute: 0),
                timeZoneIdentifier: tz,
                preferredLongBikeWeekday: 7,  // Saturday
                preferredLongRunWeekday: 1,   // Sunday
                preferredRestWeekday: 2)      // Monday

            let schedule = try engine.generateSchedule(plan: plan, config: cfg)
            let ride = try #require(schedule.first { $0.title == "Long ride" && $0.weekNumber == 2 })
            let run = try #require(schedule.first { $0.title == "Long run" && $0.weekNumber == 2 })

            #expect(cal.component(.weekday, from: ride.scheduledDate) == 7,
                    "start weekday \(startWeekday): long ride should be Saturday")
            #expect(cal.component(.weekday, from: run.scheduledDate) == 1,
                    "start weekday \(startWeekday): long run should be Sunday")
        }
    }

    @Test("A race-date-anchored plan honours preferred days too")
    func raceAnchoredHonoursPreferences() throws {
        let plan = SamplePlan.plan(weeks: 3)
        let cal = TestDates.gregorian(tz)
        // A race on a Sunday; the derived start lands on an arbitrary weekday.
        let race = TestDates.date(2026, 3, 22, tz: tz)

        let cfg = ScheduleConfiguration(
            anchor: .raceDate(race),
            startWeekday: 2,
            weekdayDefaultTime: TimeOfDay(hour: 6, minute: 30),
            weekendDefaultTime: TimeOfDay(hour: 8, minute: 0),
            timeZoneIdentifier: tz,
            preferredLongBikeWeekday: 7,
            preferredLongRunWeekday: 1,
            preferredRestWeekday: 2)

        let schedule = try ScheduleEngine().generateSchedule(plan: plan, config: cfg)
        let ride = try #require(schedule.first { $0.title == "Long ride" && $0.weekNumber == 2 })
        #expect(cal.component(.weekday, from: ride.scheduledDate) == 7,
                "race-anchored plans derive an arbitrary start weekday and were always wrong")
    }
}
