import Testing
import Foundation
@testable import EnduranceDomain

@Suite("Adaptation & reschedule conflict rules")
struct AdaptationTests {
    let advisor = AdaptationAdvisor()
    let cal = TestDates.gregorian("UTC")

    func day(_ offset: Int) -> Date { TestDates.date(2026, 6, 1, tz: "UTC").addingTimeInterval(TimeInterval(offset) * 86_400) }

    @Test("Missed options never auto-stack — all four choices are offered")
    func missedOptions() {
        let w = ScheduledFactory.make(name: "x", sport: .run, stress: .hard, start: day(0))
        #expect(Set(advisor.missedOptions(for: w)) == Set(AdaptationAdvisor.MissedOption.allCases))
    }

    @Test("Moving a high-stress session next to another high-stress day warns")
    func consecutiveHighStress() {
        let existingHard = ScheduledFactory.make(name: "hard-run", sport: .run, stress: .hard, start: day(3))
        let mover = ScheduledFactory.make(name: "long-bike", sport: .bike, stress: .long, start: day(0))
        let warnings = advisor.warningsForMoving(mover, to: day(4), within: [existingHard], calendar: cal, loadForDate: { _ in .base })
        #expect(warnings.contains { $0.kind == .consecutiveHighStress })
    }

    @Test("A long run the day after a hard run warns")
    func longRunAfterHardRun() {
        let hardRun = ScheduledFactory.make(name: "hard-run", sport: .run, stress: .hard, start: day(2))
        let longRun = ScheduledFactory.make(name: "long-run", sport: .run, stress: .long, start: day(6))
        let warnings = advisor.warningsForMoving(longRun, to: day(3), within: [hardRun], calendar: cal, loadForDate: { _ in .base })
        #expect(warnings.contains { $0.kind == .longRunAfterHardRun })
    }

    @Test("Hard bike intervals the day before the long ride warn")
    func intervalsBeforeLongRide() {
        let longRide = ScheduledFactory.make(name: "long-ride", sport: .bike, stress: .long, start: day(6))
        let intervals = ScheduledFactory.make(name: "vo2", sport: .bike, stress: .hard, intensity: .vo2, start: day(0))
        let warnings = advisor.warningsForMoving(intervals, to: day(5), within: [longRide], calendar: cal, loadForDate: { _ in .base })
        #expect(warnings.contains { $0.kind == .intervalsBeforeLongRide })
    }

    @Test("Restoring meaningful volume into a recovery week warns")
    func restoringIntoRecoveryWeek() {
        let mover = ScheduledFactory.make(name: "tempo", sport: .bike, stress: .moderate, start: day(0))
        let warnings = advisor.warningsForMoving(mover, to: day(10), within: [], calendar: cal, loadForDate: { _ in .recovery })
        #expect(warnings.contains { $0.kind == .restoringIntoRecoveryWeek })
    }

    @Test("A benign move to an empty base-week day produces no warnings")
    func benignMove() {
        let mover = ScheduledFactory.make(name: "easy", sport: .run, stress: .easy, start: day(0))
        let warnings = advisor.warningsForMoving(mover, to: day(9), within: [], calendar: cal, loadForDate: { _ in .base })
        #expect(warnings.isEmpty)
    }

    @Test("Illness guidance is conservative and non-diagnostic")
    func illnessGuidance() {
        let g = advisor.illnessOrPainGuidance()
        #expect(g.kind == .illnessOrPain)
        #expect(!g.message.isEmpty)
    }
}
