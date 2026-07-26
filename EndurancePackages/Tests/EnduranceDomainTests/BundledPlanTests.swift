import Testing
import Foundation
@testable import EnduranceDomain
import EnduranceTrainingPlans

@Suite("Bundled 36-week plan")
struct BundledPlanTests {
    let engine = ScheduleEngine()

    @Test("The bundled JSON loads and passes validation")
    func loadsAndValidates() throws {
        let plan = try BundledPlans.load36Week()
        #expect(plan.durationWeeks == 36)
        #expect(plan.weeks.count == 36)
        #expect(plan.allDays.count == 252)
        #expect(PlanValidator().validate(plan).isValid)
    }

    @Test("The committed JSON is in sync with the generator")
    func jsonMatchesGenerator() throws {
        let bundled = try BundledPlans.load36Week()
        let generated = BundledPlans.generated36Week()
        // Compare the round-tripped generator output to the bundled file.
        let a = try PlanCodec.encode(bundled)
        let b = try PlanCodec.encode(generated)
        #expect(a == b, "Run `swift run enduranceplan` to regenerate the bundled plan JSON.")
    }

    @Test("Phase structure tiles all 36 weeks and includes taper + race week")
    func phaseStructure() throws {
        let plan = try BundledPlans.load36Week()
        for w in 1...36 { #expect(plan.phase(forWeek: w) != nil) }
        #expect(plan.phase(forWeek: 36)?.name == "Race week")
        #expect(plan.weeks.first { $0.weekNumber == 36 }?.load == .race)
        #expect(plan.weeks.first { $0.weekNumber == 34 }?.load == .taper)
        // Recovery weeks every 4th week.
        for w in [4, 8, 12, 16, 20, 24, 28, 32] {
            #expect(plan.weeks.first { $0.weekNumber == w }?.load == .recovery)
        }
    }

    @Test("Race week ends with a race-day session on the final day")
    func raceDay() throws {
        let plan = try BundledPlans.load36Week()
        let config = ScheduleConfiguration(anchor: .startDate(TestDates.date(2026, 1, 5, tz: "UTC")), startWeekday: 2, timeZoneIdentifier: "UTC")
        let schedule = try engine.generateSchedule(plan: plan, config: config)
        #expect(schedule.count == 382)
        let last = schedule.max { $0.dayIndex < $1.dayIndex }!
        #expect(last.sport == .race)
        #expect(last.stressCategory == .raceSpecific)
    }

    @Test("Long runs never exceed ~2.5h (no full-marathon training run)")
    func longRunCap() throws {
        let plan = try BundledPlans.load36Week()
        let longRuns = plan.weeks.flatMap { $0.days }.flatMap { $0.workouts }
            .filter { $0.sport == .run && $0.stressCategory == .long }
        #expect(!longRuns.isEmpty)
        #expect(longRuns.allSatisfy { $0.plannedDurationMinutes <= 150 })
    }

    @Test("Every non-recovery week from base onward has a weekend brick")
    func bricksPresent() throws {
        let plan = try BundledPlans.load36Week()
        let bricksByWeek = Dictionary(grouping: plan.weeks, by: { $0.weekNumber })
        for w in 5...33 where ![8, 12, 16, 20, 24, 28, 32].contains(w) {
            let week = bricksByWeek[w]!.first!
            let hasBrick = week.days.flatMap { $0.workouts }.contains { $0.isBrick }
            #expect(hasBrick, "week \(w) should contain a brick")
        }
    }
}
