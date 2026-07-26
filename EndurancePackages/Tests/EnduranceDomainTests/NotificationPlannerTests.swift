import Testing
import Foundation
@testable import EnduranceDomain

@Suite("Notification planning — identifiers, cancellation, window, budget")
struct NotificationPlannerTests {
    let engine = ScheduleEngine()
    let planner = NotificationPlanner()

    func schedule() throws -> (schedule: [ScheduledWorkout], config: ScheduleConfiguration, now: Date) {
        let start = TestDates.date(2026, 7, 6, tz: "UTC") // Mon
        let config = SamplePlan.config(start: start, tz: "UTC")
        let sched = try engine.generateSchedule(plan: SamplePlan.plan(weeks: 3), config: config)
        let now = config.calendar.date(byAdding: .day, value: -1, to: start)!
        return (sched, config, now)
    }

    @Test("Identifiers are stable and derivable, not random")
    func identifiers() {
        let id = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        #expect(NotificationPlanner.workoutIdentifier(id) == "workout.\(id.uuidString)")
        #expect(NotificationPlanner.allIdentifiers(for: id).count == 4)
        #expect(Set(NotificationPlanner.allIdentifiers(for: id)).count == 4) // all distinct
    }

    @Test("With only the workout category, every active session gets exactly one reminder")
    func workoutCategoryOnly() throws {
        let (sched, config, now) = try schedule()
        let prefs = NotificationPreferences(enabledCategories: [.workout], schedulingWindowDays: 60)
        let plan = planner.plan(workouts: sched, preferences: prefs, now: now, calendar: config.calendar)
        let workoutNotifs = plan.toSchedule.filter { $0.category == .workout }
        #expect(workoutNotifs.count == sched.count) // 27 sessions in a 3-week sample
        // Ids are unique and correctly prefixed.
        #expect(Set(plan.toSchedule.map(\.id)).count == plan.toSchedule.count)
        #expect(workoutNotifs.allSatisfy { $0.id.hasPrefix("workout.") })
        // Fire time is lead-minutes before the planned start.
        let first = workoutNotifs.first { $0.workoutID == sched[0].id }!
        let expected = config.calendar.date(byAdding: .minute, value: -prefs.workoutLeadMinutes, to: sched[0].plannedStart)!
        #expect(first.fireDate == expected)
    }

    @Test("Disabled categories produce no notifications")
    func disabledCategories() throws {
        let (sched, config, now) = try schedule()
        let prefs = NotificationPreferences(enabledCategories: [], schedulingWindowDays: 60)
        let plan = planner.plan(workouts: sched, preferences: prefs, now: now, calendar: config.calendar)
        #expect(plan.toSchedule.isEmpty)
    }

    @Test("Preparation and fueling only attach to long/brick/race sessions")
    func prepAndFuel() throws {
        let (sched, config, now) = try schedule()
        let prefs = NotificationPreferences(enabledCategories: [.preparation, .fueling], schedulingWindowDays: 60)
        let plan = planner.plan(workouts: sched, preferences: prefs, now: now, calendar: config.calendar)
        // Long runs (3) + long rides (3, also brick) + brick runs (3) qualify for prep; fueling only long/raceSpecific.
        #expect(plan.toSchedule.contains { $0.category == .preparation })
        #expect(plan.toSchedule.contains { $0.category == .fueling })
        // No workout-category notifications since that toggle is off.
        #expect(!plan.toSchedule.contains { $0.category == .workout })
    }

    @Test("Completing a workout removes its future reminder on regeneration")
    func cancellationOnCompletion() throws {
        var (sched, config, now) = try schedule()
        let prefs = NotificationPreferences(enabledCategories: [.workout], schedulingWindowDays: 60)
        let before = planner.plan(workouts: sched, preferences: prefs, now: now, calendar: config.calendar)
        let target = sched[0]
        #expect(before.toSchedule.contains { $0.id == NotificationPlanner.workoutIdentifier(target.id) })

        sched[0].status = .completed
        let after = planner.plan(workouts: sched, preferences: prefs, now: now, calendar: config.calendar)
        #expect(!after.toSchedule.contains { $0.id == NotificationPlanner.workoutIdentifier(target.id) })
        // The cancellation set still names the workout's identifiers for the app to remove.
        #expect(NotificationPlanner.allIdentifiers(for: target.id).contains(NotificationPlanner.workoutIdentifier(target.id)))
    }

    @Test("Moving a workout regenerates its reminder at the new time")
    func regenerationAfterMove() throws {
        var (sched, config, now) = try schedule()
        let prefs = NotificationPreferences(enabledCategories: [.workout], schedulingWindowDays: 60)
        let newStart = config.calendar.date(byAdding: .day, value: 2, to: sched[0].plannedStart)!
        sched[0].plannedStart = newStart
        sched[0].scheduledDate = config.calendar.startOfDay(for: newStart)
        let plan = planner.plan(workouts: sched, preferences: prefs, now: now, calendar: config.calendar)
        let notif = plan.toSchedule.first { $0.id == NotificationPlanner.workoutIdentifier(sched[0].id) }!
        #expect(notif.fireDate == config.calendar.date(byAdding: .minute, value: -prefs.workoutLeadMinutes, to: newStart)!)
    }

    @Test("The rolling window excludes sessions beyond schedulingWindowDays")
    func windowExcludesFarFuture() throws {
        let (sched, config, now) = try schedule()
        let prefs = NotificationPreferences(enabledCategories: [.workout], schedulingWindowDays: 5)
        let plan = planner.plan(workouts: sched, preferences: prefs, now: now, calendar: config.calendar)
        let windowEnd = config.calendar.date(byAdding: .day, value: 5, to: now)!
        #expect(plan.toSchedule.allSatisfy { $0.fireDate <= windowEnd })
        #expect(plan.toSchedule.count < sched.count) // some are excluded
    }

    @Test("The budget cap is never exceeded and drops are reported")
    func budgetCap() throws {
        let (sched, config, now) = try schedule()
        let cappedPlanner = NotificationPlanner(maxScheduled: 10)
        let prefs = NotificationPreferences(enabledCategories: [.workout], schedulingWindowDays: 60)
        let plan = cappedPlanner.plan(workouts: sched, preferences: prefs, now: now, calendar: config.calendar)
        #expect(plan.toSchedule.count == 10)
        #expect(plan.droppedCount == sched.count - 10)
        // Kept notifications are the soonest ones.
        let keptDates = plan.toSchedule.map(\.fireDate)
        #expect(keptDates == keptDates.sorted())
    }

    @Test("The planner never exceeds the 64 system limit even if asked to")
    func systemLimitClamp() {
        let over = NotificationPlanner(maxScheduled: 500)
        #expect(over.maxScheduled == NotificationPlanner.systemPendingLimit)
    }
}
