import Testing
import Foundation
@testable import EnduranceDomain
@testable import EnduranceTrainingPlans

/// §G — metrics must be honest about absence, and interval position must be
/// arithmetic done once rather than in each view.
@Suite("Active workout metrics")
struct ActiveWorkoutMetricsTests {

    // MARK: - Absence

    @Test("A metric with no data is absent, never zero")
    func absentRatherThanZero() {
        let metrics = ActiveWorkoutMetrics(elapsedSeconds: 120, activeSeconds: 118)
        #expect(metrics.heartRateBPM == nil)
        #expect(metrics.distanceMeters == nil)
        #expect(metrics.currentPowerWatts == nil)
    }

    @Test("Pace is nil until distance exists, rather than infinite")
    func paceUndefinedBeforeMovement() {
        #expect(ActiveWorkoutMetrics.pace(distanceMeters: 0, activeSeconds: 30) == nil)
        #expect(ActiveWorkoutMetrics.pace(distanceMeters: nil, activeSeconds: 30) == nil)
        #expect(ActiveWorkoutMetrics.pace(distanceMeters: 1000, activeSeconds: 0) == nil)
    }

    @Test("Pace and speed agree with each other")
    func paceMatchesSpeed() throws {
        let pace = try #require(ActiveWorkoutMetrics.pace(distanceMeters: 2000, activeSeconds: 600))
        let speed = try #require(ActiveWorkoutMetrics.speed(distanceMeters: 2000, activeSeconds: 600))
        #expect(abs(pace - 300) < 0.001, "2 km in 10 min is 5:00/km")
        #expect(abs(speed - (2000.0 / 600)) < 0.001)
    }

    @Test("Only metrics a sport can produce are offered")
    func sportRelevantFields() {
        #expect(ActiveWorkoutMetrics.relevantFields(for: .bike).contains(.power))
        #expect(!ActiveWorkoutMetrics.relevantFields(for: .run).contains(.power))
        #expect(!ActiveWorkoutMetrics.relevantFields(for: .strength).contains(.distance),
                "a strength session has no distance to show")
    }

    // MARK: - Monotonic timing (§G)

    @Test("Elapsed time comes from a monotonic clock and survives pause/resume")
    func stopwatchAccumulates() {
        var watch = MonotonicStopwatch()
        let second: UInt64 = 1_000_000_000
        watch.start(now: 0)
        #expect(watch.elapsed(now: 10 * second) == 10)
        watch.pause(now: 10 * second)
        #expect(watch.elapsed(now: 60 * second) == 10, "a paused watch must not accrue")
        watch.start(now: 60 * second)
        #expect(watch.elapsed(now: 65 * second) == 15)
    }

    @Test("A backwards clock reading cannot subtract time")
    func stopwatchIgnoresBackwardsTime() {
        var watch = MonotonicStopwatch()
        watch.start(now: 100)
        #expect(watch.elapsed(now: 50) == 0, "time must never go negative")
    }

    // MARK: - Interval position

    private func steps(_ specs: [(String, Int?, Double?, Int)]) -> [WorkoutStep] {
        specs.map { label, seconds, meters, repeats in
            WorkoutStep(kind: .work, label: label, durationSeconds: seconds,
                        distanceMeters: meters, intensity: nil, repeats: repeats,
                        childSteps: [], note: nil)
        }
    }

    @Test("Repeats are expanded — four repeats are four steps to the athlete")
    func repeatsExpand() {
        let tracker = IntervalTracker(steps: steps([("400m", nil, 400, 4)]))
        #expect(tracker.totalSteps == 4)
    }

    @Test("Progress reports the current and the upcoming step")
    func reportsCurrentAndNext() throws {
        let tracker = IntervalTracker(steps: steps([
            ("Warm up", 600, nil, 1), ("Effort", 300, nil, 1), ("Cool down", 300, nil, 1),
        ]))
        let progress = tracker.progress(atIndex: 1, elapsedInStep: 60)
        #expect(progress.current?.label == "Effort")
        #expect(progress.upcoming?.label == "Cool down")
        #expect(progress.remainingSeconds == 240)
    }

    @Test("The last step has no upcoming step")
    func lastStepHasNoSuccessor() {
        let tracker = IntervalTracker(steps: steps([("Only", 60, nil, 1)]))
        #expect(tracker.progress(atIndex: 0).upcoming == nil)
    }

    @Test("Remaining never goes negative when a step is overrun")
    func remainingClampsAtZero() {
        let tracker = IntervalTracker(steps: steps([("Effort", 300, nil, 1)]))
        let progress = tracker.progress(atIndex: 0, elapsedInStep: 900)
        #expect(progress.remainingSeconds == 0)
    }

    @Test("A step with no stated goal is never auto-completed")
    func openStepNeedsAthleteJudgement() {
        let tracker = IntervalTracker(steps: steps([("Easy, as you feel", nil, nil, 1)]))
        #expect(!tracker.isStepComplete(atIndex: 0, elapsedInStep: 9_999, distanceInStep: 9_999),
                "advancing past an open step would be guessing on the athlete's behalf")
    }

    @Test("Duration and distance goals each complete their step")
    func statedGoalsComplete() {
        let byTime = IntervalTracker(steps: steps([("3 min", 180, nil, 1)]))
        #expect(byTime.isStepComplete(atIndex: 0, elapsedInStep: 180, distanceInStep: 0))
        let byDistance = IntervalTracker(steps: steps([("400 m", nil, 400, 1)]))
        #expect(byDistance.isStepComplete(atIndex: 0, elapsedInStep: 0, distanceInStep: 400))
    }

    @Test("A real bundled session flattens into a sensible number of steps")
    func realTemplateFlattens() throws {
        let plan = try BundledPlans.load36Week()
        let template = try #require(
            plan.weeks.flatMap(\.days).flatMap(\.workouts).first { $0.sport == .swim && !$0.mainSet.isEmpty })
        let tracker = IntervalTracker(template: template)
        #expect(tracker.totalSteps > 0)
        #expect(tracker.progress(atIndex: 0).current != nil)
    }
}
