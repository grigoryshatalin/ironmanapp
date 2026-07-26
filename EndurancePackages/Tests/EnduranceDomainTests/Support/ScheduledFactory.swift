import Foundation
@testable import EnduranceDomain

/// Builds individual `ScheduledWorkout`s with precise control for the progress,
/// notification, and adaptation tests.
enum ScheduledFactory {
    static func make(
        name: String,
        sport: Sport,
        stress: StressCategory,
        intensity: IntensityZone = .endurance,
        start: Date,
        durationMinutes: Int = 60,
        distanceMeters: Double? = nil,
        weekNumber: Int = 1,
        dayIndex: Int = 0,
        isOptional: Bool = false,
        status: WorkoutStatus = .planned,
        completion: WorkoutCompletion? = nil
    ) -> ScheduledWorkout {
        let sid = UUIDv5.make(namespace: UUIDv5.Namespace.enduranceSchedule, name: "sched:\(name)")
        let cal = TestDates.gregorian("UTC")
        return ScheduledWorkout(
            identity: WorkoutIdentity(scheduledWorkoutID: sid),
            weekNumber: weekNumber,
            weekdayOffset: dayIndex % 7,
            dayIndex: dayIndex,
            order: 0,
            sport: sport,
            title: name,
            objective: "\(name) objective",
            plannedDurationMinutes: durationMinutes,
            plannedDistanceMeters: distanceMeters,
            intensity: intensity,
            stressCategory: stress,
            isOptional: isOptional,
            originalDate: cal.startOfDay(for: start),
            scheduledDate: cal.startOfDay(for: start),
            plannedStart: start,
            status: status,
            completion: completion)
    }
}
