import Testing
import Foundation
@testable import EnduranceDomain

@Suite("Plan lookup")
struct PlanLookupTests {
    @Test("Phase lookup returns the phase covering a week")
    func phaseForWeek() {
        let plan = SamplePlan.plan(weeks: 3)
        #expect(plan.phase(forWeek: 1)?.name == "Base")
        #expect(plan.phase(forWeek: 2)?.name == "Base")
        #expect(plan.phase(forWeek: 3)?.name == "Recovery")
        #expect(plan.phase(forWeek: 99) == nil)
    }

    @Test("allDays is chronological and complete")
    func allDays() {
        let plan = SamplePlan.plan(weeks: 3)
        let days = plan.allDays
        #expect(days.count == 21)
        #expect(days.map(\.dayIndex) == Array(0..<21))
    }
}

@Suite("Plan validation")
struct PlanValidationTests {
    let validator = PlanValidator()

    @Test("A well-formed sample plan validates with no errors")
    func validPlan() {
        let result = validator.validate(SamplePlan.plan(weeks: 3))
        #expect(result.isValid, "unexpected errors: \(result.errors)")
    }

    @Test("Mismatched durationWeeks vs week count is an error")
    func weekCountMismatch() {
        var plan = SamplePlan.plan(weeks: 3)
        plan.durationWeeks = 5
        let result = validator.validate(plan)
        #expect(!result.isValid)
        #expect(result.errors.contains { $0.code == "plan.weekCount" })
    }

    @Test("A wrong dayIndex is caught")
    func badDayIndex() {
        var plan = SamplePlan.plan(weeks: 2)
        plan.weeks[0].days[3].dayIndex = 999
        let result = validator.validate(plan)
        #expect(result.errors.contains { $0.code == "day.index" })
    }

    @Test("A gap in phase coverage is an error")
    func phaseGap() {
        var plan = SamplePlan.plan(weeks: 3)
        // Make the base phase start at week 2 → week 1 uncovered + gap.
        plan.phases[0].startWeek = 2
        let result = validator.validate(plan)
        #expect(!result.isValid)
        #expect(result.errors.contains { $0.code == "phase.gap" || $0.code == "week.noPhase" })
    }

    @Test("A negative distance is rejected")
    func negativeDistance() {
        var plan = SamplePlan.plan(weeks: 2)
        plan.weeks[0].days[2].workouts[0].plannedDistanceMeters = -100
        let result = validator.validate(plan)
        #expect(result.errors.contains { $0.code == "workout.distance" })
    }

    @Test("A future schema version is unsupported")
    func futureSchema() {
        var plan = SamplePlan.plan(weeks: 2)
        plan.schemaVersion = EnduranceDomain.currentPlanSchemaVersion + 1
        let result = validator.validate(plan)
        #expect(result.errors.contains { $0.code == "schema.unsupported" })
    }

    @Test("An orphaned brick member is an error")
    func brickIncomplete() {
        var plan = SamplePlan.plan(weeks: 2)
        // Remove the brick run, leaving the bike alone in its group.
        plan.weeks[0].days[5].workouts.removeLast()
        let result = validator.validate(plan)
        #expect(result.errors.contains { $0.code == "brick.incomplete" })
    }
}
