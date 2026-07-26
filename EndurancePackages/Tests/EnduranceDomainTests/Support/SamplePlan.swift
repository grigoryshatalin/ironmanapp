import Foundation
@testable import EnduranceDomain

/// Builds small, *valid* plans for tests. Deterministic ids (via UUIDv5) so
/// assertions are stable across runs. This lives in the test target only — the
/// production app never depends on it (§26).
enum SamplePlan {

    static let planID = UUIDv5.make(namespace: UUIDv5.Namespace.enduranceSchedule, name: "sample-plan")

    static func templateID(week: Int, offset: Int, slot: Int) -> UUID {
        UUIDv5.make(namespace: UUIDv5.Namespace.enduranceSchedule, name: "tmpl:w\(week):o\(offset):s\(slot)")
    }

    /// A plan with `weeks` weeks; the final week is a recovery week.
    static func plan(weeks: Int = 3) -> TrainingPlanDefinition {
        let phaseBase = TrainingPhaseDefinition(
            id: UUIDv5.make(namespace: UUIDv5.Namespace.enduranceSchedule, name: "phase-base"),
            name: "Base", startWeek: 1, endWeek: max(1, weeks - 1),
            objective: "Build aerobic base", defaultLoad: .base)
        let phaseRecovery = TrainingPhaseDefinition(
            id: UUIDv5.make(namespace: UUIDv5.Namespace.enduranceSchedule, name: "phase-recovery"),
            name: "Recovery", startWeek: weeks, endWeek: weeks,
            objective: "Absorb training", defaultLoad: .recovery)

        var weekDefs: [TrainingWeekDefinition] = []
        for w in 1...weeks {
            let isRecovery = (w == weeks)
            let days = (0...6).map { day(week: w, offset: $0, recovery: isRecovery) }
            let minutes = days.flatMap { $0.workouts }.reduce(0) { $0 + $1.plannedDurationMinutes }
            weekDefs.append(TrainingWeekDefinition(
                id: UUIDv5.make(namespace: UUIDv5.Namespace.enduranceSchedule, name: "week-\(w)"),
                weekNumber: w,
                phaseID: isRecovery ? phaseRecovery.id : phaseBase.id,
                title: isRecovery ? "Week \(w) — Recovery" : "Week \(w)",
                objective: isRecovery ? "Recover" : "Consistent aerobic work",
                load: isRecovery ? .recovery : .base,
                plannedMinutes: minutes,
                days: days))
        }

        let phases = weeks >= 2 ? [phaseBase, phaseRecovery] : [phaseBase]
        return TrainingPlanDefinition(
            id: planID,
            schemaVersion: EnduranceDomain.currentPlanSchemaVersion,
            name: "Sample",
            summary: "A small valid plan for tests.",
            durationWeeks: weeks,
            startWeekday: 2,
            phases: phases,
            weeks: weekDefs,
            metadata: PlanMetadata(
                author: "tests", version: "1.0", athleteLevel: "first-timer",
                goal: "finish", disclaimer: "Not medical advice."))
    }

    private static func day(week: Int, offset: Int, recovery: Bool) -> TrainingDayDefinition {
        let dayIndex = (week - 1) * 7 + offset
        let scale = recovery ? 0.6 : 1.0
        func mins(_ m: Int) -> Int { max(15, Int(Double(m) * scale)) }

        var workouts: [WorkoutTemplate] = []
        switch offset {
        case 0: // Mon — recovery/mobility
            workouts = [wt(week, offset, 0, .mobility, "Mobility & technique", mins(30), nil, .recovery, .recovery)]
        case 1: // Tue — quality bike
            workouts = [wt(week, offset, 0, .bike, "Bike intervals", mins(60), 30000, .tempo, recovery ? .moderate : .moderate)]
        case 2: // Wed — swim + easy run
            workouts = [
                wt(week, offset, 0, .swim, "Swim endurance", mins(45), 2000, .endurance, .moderate),
                wt(week, offset, 1, .run, "Easy run", mins(30), 5000, .endurance, .easy, order: 1)
            ]
        case 3: // Thu — quality run
            workouts = [wt(week, offset, 0, .run, "Run threshold", mins(50), 9000, .threshold, recovery ? .moderate : .hard)]
        case 4: // Fri — technique swim
            workouts = [wt(week, offset, 0, .swim, "Technique swim", mins(40), 1500, .recovery, .recovery)]
        case 5: // Sat — long bike + brick run
            let brickID = UUIDv5.make(namespace: UUIDv5.Namespace.enduranceSchedule, name: "brick:w\(week)")
            workouts = [
                wtBrick(week, offset, 0, .bike, "Long ride", mins(180), 60000, .endurance, .long, brickID, order: 0),
                wtBrick(week, offset, 1, .run, "Brick run", mins(20), 3500, .tempo, .moderate, brickID, order: 1)
            ]
        case 6: // Sun — long run
            workouts = [wt(week, offset, 0, .run, "Long run", mins(90), 16000, .endurance, .long,
                           fueling: FuelingGuidance(carbsGramsPerHourLow: 30, carbsGramsPerHourHigh: 60, note: "Practice race fueling", isKeyFuelingSession: true))]
        default:
            workouts = []
        }

        return TrainingDayDefinition(
            id: UUIDv5.make(namespace: UUIDv5.Namespace.enduranceSchedule, name: "day:w\(week):o\(offset)"),
            dayIndex: dayIndex, weekdayOffset: offset,
            title: "Day \(offset)", objective: "Train", workouts: workouts,
            recovery: RecoveryGuidance(summary: "Sleep well."))
    }

    private static func wt(
        _ week: Int, _ offset: Int, _ slot: Int, _ sport: Sport, _ title: String,
        _ minutes: Int, _ distance: Double?, _ intensity: IntensityZone, _ stress: StressCategory,
        order: Int = 0, fueling: FuelingGuidance? = nil
    ) -> WorkoutTemplate {
        WorkoutTemplate(
            id: templateID(week: week, offset: offset, slot: slot),
            sport: sport, title: title, objective: "\(title) objective",
            plannedDurationMinutes: minutes, plannedDistanceMeters: distance,
            intensity: intensity, stressCategory: stress, order: order,
            fueling: fueling)
    }

    private static func wtBrick(
        _ week: Int, _ offset: Int, _ slot: Int, _ sport: Sport, _ title: String,
        _ minutes: Int, _ distance: Double?, _ intensity: IntensityZone, _ stress: StressCategory,
        _ brickID: UUID, order: Int
    ) -> WorkoutTemplate {
        WorkoutTemplate(
            id: templateID(week: week, offset: offset, slot: slot),
            sport: sport, title: title, objective: "\(title) objective",
            plannedDurationMinutes: minutes, plannedDistanceMeters: distance,
            intensity: intensity, stressCategory: stress, order: order,
            isBrick: true, brickGroupID: brickID)
    }

    /// A default configuration anchored at a start date in a given zone.
    static func config(start: Date, tz: String = "America/New_York") -> ScheduleConfiguration {
        ScheduleConfiguration(
            anchor: .startDate(start),
            startWeekday: 2,
            weekdayDefaultTime: TimeOfDay(hour: 6, minute: 30),
            weekendDefaultTime: TimeOfDay(hour: 8, minute: 0),
            timeZoneIdentifier: tz)
    }
}
