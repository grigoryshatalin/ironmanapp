import Testing
import Foundation
@testable import EnduranceDomain

@Suite("Progress aggregation")
struct ProgressTests {
    let calc = ProgressCalculator()

    /// Build a small week of scheduled workouts we fully control.
    func week() -> [ScheduledWorkout] {
        let base = TestDates.date(2026, 6, 1, tz: "UTC")
        return [
            ScheduledFactory.make(name: "swim", sport: .swim, stress: .moderate, start: base, durationMinutes: 45, distanceMeters: 2000, dayIndex: 0),
            ScheduledFactory.make(name: "bike", sport: .bike, stress: .long, start: base, durationMinutes: 120, distanceMeters: 40000, dayIndex: 1),
            ScheduledFactory.make(name: "run", sport: .run, stress: .hard, start: base, durationMinutes: 60, distanceMeters: 10000, dayIndex: 2),
            ScheduledFactory.make(name: "opt", sport: .swim, stress: .recovery, start: base, durationMinutes: 30, distanceMeters: 1000, dayIndex: 3, isOptional: true),
        ]
    }

    @Test("Planned minutes exclude optional sessions")
    func plannedExcludesOptional() {
        let wp = calc.weekProgress(1, in: week())
        #expect(wp.plannedMinutes == 45 + 120 + 60) // optional 30 excluded
        #expect(wp.sessionCount == 3)
        #expect(wp.completedSessionCount == 0)
        #expect(wp.completionFraction == 0)
    }

    @Test("Completion counts logged actuals and reaches 100% when all planned done")
    func completion() {
        var w = week()
        // Complete the 3 non-optional sessions at their planned durations.
        for i in 0..<3 {
            w[i].status = .completed
            w[i].completion = WorkoutCompletion(completedAt: w[i].plannedStart, actualDurationMinutes: w[i].plannedDurationMinutes)
        }
        let wp = calc.weekProgress(1, in: w)
        #expect(wp.completedMinutes == 45 + 120 + 60)
        #expect(wp.completionFraction == 1.0)
        #expect(wp.completedSessionCount == 3)
    }

    @Test("A shortened, partially-completed session counts its actual time")
    func partial() {
        var w = week()
        w[1].status = .partiallyCompleted
        w[1].completion = WorkoutCompletion(completedAt: w[1].plannedStart, actualDurationMinutes: 80)
        let wp = calc.weekProgress(1, in: w)
        #expect(wp.completedMinutes == 80)
        #expect(wp.completedSessionCount == 1)
        #expect(abs(wp.completionFraction - 80.0 / 225.0) < 1e-9)
    }

    @Test("Longest completed session is reported per sport")
    func longest() {
        var w = week()
        w[1].status = .completed
        w[1].completion = WorkoutCompletion(completedAt: w[1].plannedStart, actualDurationMinutes: 130)
        #expect(calc.longestCompletedMinutes(sport: .bike, in: w) == 130)
        #expect(calc.longestCompletedMinutes(sport: .run, in: w) == nil)
    }

    @Test("Per-sport breakdown aggregates distance and duration")
    func bySport() {
        var w = week()
        w[0].status = .completed
        w[0].completion = WorkoutCompletion(completedAt: w[0].plannedStart, actualDurationMinutes: 50, actualDistanceMeters: 2100)
        let wp = calc.weekProgress(1, in: w)
        let swim = wp.bySport.first { $0.sport == .swim && $0.sessionCount > 0 }!
        #expect(swim.completedMinutes == 50)
        #expect(swim.completedDistanceMeters == 2100)
    }

    @Test("Consistency over recent weeks is the mean of weekly completion")
    func consistency() {
        // Week 1 fully done, week 2 nothing.
        var all: [ScheduledWorkout] = []
        var w1 = week(); for i in 0..<3 { w1[i].status = .completed; w1[i].completion = WorkoutCompletion(completedAt: w1[i].plannedStart, actualDurationMinutes: w1[i].plannedDurationMinutes) }
        var w2 = week(); for i in w2.indices { w2[i] = ScheduledFactory.make(name: "w2-\(i)", sport: w2[i].sport, stress: w2[i].stressCategory, start: w2[i].plannedStart, durationMinutes: w2[i].plannedDurationMinutes, weekNumber: 2, dayIndex: 7 + i, isOptional: w2[i].isOptional) }
        all = w1 + w2
        let c = calc.consistency(lastWeeks: 2, endingAt: 2, in: all)
        #expect(abs(c - 0.5) < 1e-9) // 1.0 and 0.0 → mean 0.5
    }
}
