import Testing
import Foundation
@testable import EnduranceDomain

@Suite("Schedule engine — dates, DST, leap years, conversion")
struct SchedulingTests {
    let engine = ScheduleEngine()

    @Test("Day 0 equals the start date; day N is N calendar days later")
    func dayIndexing() throws {
        let start = TestDates.date(2026, 8, 3) // Mon
        let config = SamplePlan.config(start: start)
        let plan = SamplePlan.plan(weeks: 3)
        let startDay = try engine.startDay(plan: plan, config: config)
        let cal = config.calendar

        #expect(cal.isDate(engine.date(forDayIndex: 0, startDay: startDay, config: config), inSameDayAs: start))
        let day10 = engine.date(forDayIndex: 10, startDay: startDay, config: config)
        #expect(cal.dateComponents([.day], from: startDay, to: day10).day == 10)
    }

    @Test("Local workout time is preserved across the spring-forward DST boundary")
    func dstSpringForward() throws {
        // US spring-forward is 2026-03-08. Anchor the plan so days span it.
        let start = TestDates.date(2026, 3, 1, tz: "America/New_York") // Sunday
        let config = SamplePlan.config(start: start, tz: "America/New_York")
        let cal = config.calendar
        let startDay = try engine.startDay(plan: SamplePlan.plan(), config: config)

        // A weekday template with no fixed time uses the 06:30 weekday default.
        let weekdayTemplate = WorkoutTemplate(sport: .run, title: "t", objective: "o",
                                              plannedDurationMinutes: 30, intensity: .endurance, stressCategory: .easy)

        // 2026-03-09 is the Monday AFTER the transition (dayIndex 8 from Mar 1).
        let mondayAfter = engine.date(forDayIndex: 8, startDay: startDay, config: config)
        #expect(cal.component(.month, from: mondayAfter) == 3)
        #expect(cal.component(.day, from: mondayAfter) == 9)
        let startInstant = engine.plannedStart(dayDate: mondayAfter, template: weekdayTemplate, config: config)
        #expect(cal.component(.hour, from: startInstant) == 6)
        #expect(cal.component(.minute, from: startInstant) == 30)

        // 2026-03-08 (Sunday, the transition day) uses the weekend 08:00 default.
        let transitionSunday = engine.date(forDayIndex: 7, startDay: startDay, config: config)
        #expect(cal.component(.day, from: transitionSunday) == 8)
        let sundayInstant = engine.plannedStart(dayDate: transitionSunday, template: weekdayTemplate, config: config)
        #expect(cal.component(.hour, from: sundayInstant) == 8)
    }

    @Test("Local workout time is preserved across the fall-back DST boundary")
    func dstFallBack() throws {
        // US fall-back is 2026-11-01.
        let start = TestDates.date(2026, 10, 26, tz: "America/New_York") // Mon
        let config = SamplePlan.config(start: start, tz: "America/New_York")
        let cal = config.calendar
        let startDay = try engine.startDay(plan: SamplePlan.plan(), config: config)
        let weekdayTemplate = WorkoutTemplate(sport: .run, title: "t", objective: "o",
                                              plannedDurationMinutes: 30, intensity: .endurance, stressCategory: .easy)
        // 2026-11-02 Monday after fall-back = dayIndex 7.
        let mondayAfter = engine.date(forDayIndex: 7, startDay: startDay, config: config)
        #expect(cal.component(.day, from: mondayAfter) == 2)
        let instant = engine.plannedStart(dayDate: mondayAfter, template: weekdayTemplate, config: config)
        #expect(cal.component(.hour, from: instant) == 6)
        #expect(cal.component(.minute, from: instant) == 30)
    }

    @Test("Adding a day across a leap-day boundary lands on Feb 29")
    func leapYear() throws {
        let start = TestDates.date(2028, 2, 28, tz: "UTC") // 2028 is a leap year
        let config = SamplePlan.config(start: start, tz: "UTC")
        let cal = config.calendar
        let startDay = try engine.startDay(plan: SamplePlan.plan(), config: config)
        let next = engine.date(forDayIndex: 1, startDay: startDay, config: config)
        #expect(cal.component(.month, from: next) == 2)
        #expect(cal.component(.day, from: next) == 29)
    }

    @Test("Race-date and start-date anchors are exact inverses")
    func raceStartConversion() throws {
        let plan = SamplePlan.plan(weeks: 4) // 28 days
        let start = TestDates.date(2026, 1, 5, tz: "UTC")
        let config = SamplePlan.config(start: start, tz: "UTC")

        let race = try engine.raceDay(fromStart: start, plan: plan, config: config)
        // 28 days total → race day is start + 27 days.
        #expect(config.calendar.dateComponents([.day], from: start, to: race).day == plan.totalDays - 1)

        let backToStart = try engine.startDay(fromRace: race, plan: plan, config: config)
        #expect(config.calendar.isDate(backToStart, inSameDayAs: start))
    }

    @Test("Generating under a race-date anchor puts the final day on the race date")
    func generateUnderRaceAnchor() throws {
        let plan = SamplePlan.plan(weeks: 3) // 21 days
        let raceDate = TestDates.date(2026, 9, 20, tz: "UTC")
        let config = ScheduleConfiguration(anchor: .raceDate(raceDate), startWeekday: 2, timeZoneIdentifier: "UTC")
        let schedule = try engine.generateSchedule(plan: plan, config: config)
        let lastDay = schedule.map(\.scheduledDate).max()!
        #expect(config.calendar.isDate(lastDay, inSameDayAs: raceDate))
    }

    @Test("Schedule generation is deterministic: same inputs → same ids")
    func deterministicGeneration() throws {
        let plan = SamplePlan.plan(weeks: 2)
        let config = SamplePlan.config(start: TestDates.date(2026, 5, 4, tz: "UTC"), tz: "UTC")
        let a = try engine.generateSchedule(plan: plan, config: config)
        let b = try engine.generateSchedule(plan: plan, config: config)
        #expect(a.map(\.id) == b.map(\.id))
        // Every id is unique.
        #expect(Set(a.map(\.id)).count == a.count)
    }

    @Test("Every plan workout produces exactly one scheduled instance")
    func coverage() throws {
        let plan = SamplePlan.plan(weeks: 3)
        let config = SamplePlan.config(start: TestDates.date(2026, 5, 4, tz: "UTC"), tz: "UTC")
        let schedule = try engine.generateSchedule(plan: plan, config: config)
        let expected = plan.weeks.flatMap { $0.days }.reduce(0) { $0 + $1.workouts.count }
        #expect(schedule.count == expected)
    }
}
