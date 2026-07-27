import Foundation

/// Deterministic mapping from immutable plan content to real calendar dates.
///
/// Design rules (§17):
///   * All date math uses `Calendar` + `DateComponents`, never raw seconds, so
///     it is correct across DST transitions and leap years.
///   * Local workout *time* is applied by setting hour/minute on the local day,
///     so a 6:30 AM session stays 6:30 AM local even across a DST change.
///   * Either the start date or the race date is authoritative; the other is
///     derived. Day 0 is the start; the final day (`totalDays - 1`) is race day.
public struct ScheduleEngine: Sendable {

    public enum ScheduleError: Error, Sendable, Equatable {
        case emptyPlan
        case invalidAnchor
    }

    public init() {}

    // MARK: - Start / race date conversion

    /// The start-of-day date for plan day 0, resolved from the anchor.
    public func startDay(plan: TrainingPlanDefinition, config: ScheduleConfiguration) throws -> Date {
        guard plan.totalDays > 0 else { throw ScheduleError.emptyPlan }
        let cal = config.calendar
        switch config.anchor {
        case .startDate(let d):
            return cal.startOfDay(for: d)
        case .raceDate(let raceDate):
            // Race day is the last plan day; step back (totalDays - 1) calendar days.
            let raceDay = cal.startOfDay(for: raceDate)
            guard let start = cal.date(byAdding: .day, value: -(plan.totalDays - 1), to: raceDay) else {
                throw ScheduleError.invalidAnchor
            }
            return start
        }
    }

    /// The race day (last plan day) for a given start date.
    public func raceDay(fromStart start: Date, plan: TrainingPlanDefinition, config: ScheduleConfiguration) throws -> Date {
        guard plan.totalDays > 0 else { throw ScheduleError.emptyPlan }
        let cal = config.calendar
        let start0 = cal.startOfDay(for: start)
        guard let race = cal.date(byAdding: .day, value: plan.totalDays - 1, to: start0) else {
            throw ScheduleError.invalidAnchor
        }
        return race
    }

    /// The start date implied by a race date (inverse of `raceDay(fromStart:)`).
    public func startDay(fromRace race: Date, plan: TrainingPlanDefinition, config: ScheduleConfiguration) throws -> Date {
        guard plan.totalDays > 0 else { throw ScheduleError.emptyPlan }
        let cal = config.calendar
        let race0 = cal.startOfDay(for: race)
        guard let start = cal.date(byAdding: .day, value: -(plan.totalDays - 1), to: race0) else {
            throw ScheduleError.invalidAnchor
        }
        return start
    }

    // MARK: - Per-day dates

    /// Start-of-day date for a given global day index (0-based).
    public func date(forDayIndex dayIndex: Int, startDay: Date, config: ScheduleConfiguration) -> Date {
        let cal = config.calendar
        // Adding calendar days (not seconds) keeps this correct across DST/leap.
        return cal.date(byAdding: .day, value: dayIndex, to: startDay) ?? startDay
    }

    /// The planned start instant for a workout: the day's date with the resolved
    /// local time-of-day applied. DST-safe because we set hour/minute on the
    /// local day rather than adding seconds.
    public func plannedStart(
        dayDate: Date,
        template: WorkoutTemplate,
        config: ScheduleConfiguration
    ) -> Date {
        let cal = config.calendar
        let weekday = cal.component(.weekday, from: dayDate) // 1 = Sun … 7 = Sat
        let isWeekend = (weekday == 1 || weekday == 7)
        let base = isWeekend ? config.weekendDefaultTime : config.weekdayDefaultTime
        let hour = template.preferredHour ?? base.hour
        let minute = template.preferredMinute ?? base.minute
        return cal.date(bySettingHour: hour, minute: minute, second: 0, of: dayDate) ?? dayDate
    }

    // MARK: - Full schedule generation

    /// Generate scheduled instances for every workout in the plan. New instances
    /// only — merging with existing user state is the repository's job (§18,
    /// "recalculate only future planned schedule entries when the plan moves").
    public func generateSchedule(
        plan: TrainingPlanDefinition,
        config: ScheduleConfiguration
    ) throws -> [ScheduledWorkout] {
        let start = try startDay(plan: plan, config: config)
        // The weekday plan day 0 genuinely lands on. Both anchors resolve here,
        // so a race-date-anchored plan (which counts back 251 days onto an
        // arbitrary weekday) is handled the same as a start-date one.
        let planStartWeekday = config.calendar.component(.weekday, from: start)
        var result: [ScheduledWorkout] = []
        result.reserveCapacity(plan.weeks.reduce(0) { $0 + $1.days.reduce(0) { $0 + $1.workouts.count } })

        for week in plan.weeks.sorted(by: { $0.weekNumber < $1.weekNumber }) {
            // Honour the athlete's preferred long-ride / long-run / rest days by
            // permuting whole days within the week (§7). Identity layout when no
            // preference was expressed, so the plan's own rhythm is used as-is.
            let layout = WeekdayLayout.make(for: week, config: config, planStartWeekday: planStartWeekday)
            let weekFirstDayIndex = (week.weekNumber - 1) * 7

            for day in week.days.sorted(by: { $0.weekdayOffset < $1.weekdayOffset }) {
                let effectiveOffset = layout.destination(for: day.weekdayOffset)
                let effectiveDayIndex = weekFirstDayIndex + effectiveOffset
                let dayDate = date(forDayIndex: effectiveDayIndex, startDay: start, config: config)
                for template in day.workouts.sorted(by: { $0.order < $1.order }) {
                    let startInstant = plannedStart(dayDate: dayDate, template: template, config: config)
                    let identity = WorkoutIdentity(
                        planID: plan.id,
                        templateID: template.id,
                        // Derived from the plan's CANONICAL day index, not the
                        // permuted one, so a workout keeps its identity — and its
                        // completion history — if the athlete later changes which
                        // weekday carries the long ride (§28.2).
                        scheduledWorkoutID: deterministicScheduledID(planID: plan.id, templateID: template.id, dayIndex: day.dayIndex),
                        externalReferences: []
                    )
                    let scheduled = ScheduledWorkout(
                        identity: identity,
                        weekNumber: week.weekNumber,
                        weekdayOffset: effectiveOffset,
                        dayIndex: effectiveDayIndex,
                        order: template.order,
                        sport: template.sport,
                        title: template.title,
                        objective: template.objective,
                        plannedDurationMinutes: template.plannedDurationMinutes,
                        plannedDistanceMeters: template.plannedDistanceMeters,
                        intensity: template.intensity,
                        stressCategory: template.stressCategory,
                        isBrick: template.isBrick,
                        brickGroupID: template.brickGroupID,
                        isOptional: template.isOptional,
                        originalDate: dayDate,
                        scheduledDate: dayDate,
                        plannedStart: startInstant,
                        status: .planned
                    )
                    result.append(scheduled)
                }
            }
        }
        return result
    }

    /// A stable, deterministic scheduled-workout id derived from plan + template
    /// + day index. Deterministic ids mean regeneration (after a date change or
    /// re-import) reconciles to the SAME instances rather than duplicating them
    /// (§18, §28.2 "identifiers or deterministic identifiers").
    public func deterministicScheduledID(planID: UUID, templateID: UUID, dayIndex: Int) -> UUID {
        UUIDv5.make(namespace: UUIDv5.Namespace.enduranceSchedule, name: "\(planID.uuidString):\(templateID.uuidString):\(dayIndex)")
    }
}
