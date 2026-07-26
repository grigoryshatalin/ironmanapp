import Foundation

/// Validates a decoded plan against the invariants the rest of the app relies
/// on. Returns a structured result (errors block import; warnings inform the
/// author) rather than trapping — malformed content must degrade gracefully.
public struct PlanValidator: Sendable {

    public enum Severity: String, Sendable, Hashable { case error, warning }

    public struct Issue: Sendable, Hashable, CustomStringConvertible {
        public var severity: Severity
        public var code: String
        public var message: String
        public var location: String
        public var description: String { "[\(severity.rawValue.uppercased())] \(code) — \(message) (\(location))" }
    }

    public struct Result: Sendable, Hashable {
        public var issues: [Issue]
        public var errors: [Issue] { issues.filter { $0.severity == .error } }
        public var warnings: [Issue] { issues.filter { $0.severity == .warning } }
        public var isValid: Bool { errors.isEmpty }
    }

    /// How far off the declared weekly minutes may be from the summed session
    /// minutes before we warn. Content authoring aid only.
    public var plannedMinutesTolerance: Double

    public init(plannedMinutesTolerance: Double = 0.35) {
        self.plannedMinutesTolerance = plannedMinutesTolerance
    }

    public func validate(_ plan: TrainingPlanDefinition) -> Result {
        var issues: [Issue] = []
        func err(_ code: String, _ msg: String, _ loc: String) { issues.append(.init(severity: .error, code: code, message: msg, location: loc)) }
        func warn(_ code: String, _ msg: String, _ loc: String) { issues.append(.init(severity: .warning, code: code, message: msg, location: loc)) }

        // Schema version
        if plan.schemaVersion > EnduranceDomain.currentPlanSchemaVersion {
            err("schema.unsupported",
                "Plan schema v\(plan.schemaVersion) is newer than this app supports (v\(EnduranceDomain.currentPlanSchemaVersion)). Update the app.",
                "plan")
        }
        if plan.schemaVersion < 1 {
            err("schema.invalid", "Schema version must be >= 1.", "plan")
        }

        // Duration / week count
        if plan.durationWeeks <= 0 {
            err("plan.duration", "durationWeeks must be positive.", "plan")
        }
        if plan.weeks.count != plan.durationWeeks {
            err("plan.weekCount",
                "durationWeeks (\(plan.durationWeeks)) does not match number of weeks (\(plan.weeks.count)).",
                "plan.weeks")
        }
        if !(1...7).contains(plan.startWeekday) {
            err("plan.startWeekday", "startWeekday must be 1–7 (Gregorian).", "plan")
        }

        // Week numbers contiguous & unique
        let weekNumbers = plan.weeks.map(\.weekNumber).sorted()
        if Set(weekNumbers).count != weekNumbers.count {
            err("weeks.duplicate", "Duplicate week numbers found.", "plan.weeks")
        }
        for (i, n) in weekNumbers.enumerated() where n != i + 1 {
            err("weeks.noncontiguous", "Week numbers must be 1…\(plan.durationWeeks) with no gaps; found \(n) at position \(i + 1).", "plan.weeks")
            break
        }

        // Phases cover weeks without gaps/overlap
        validatePhases(plan, err: err, warn: warn)

        // Per-week / per-day checks
        var seenDayIndices = Set<Int>()
        for week in plan.weeks.sorted(by: { $0.weekNumber < $1.weekNumber }) {
            let loc = "week \(week.weekNumber)"
            if plan.phase(forWeek: week.weekNumber) == nil {
                err("week.noPhase", "Week is not covered by any phase.", loc)
            }
            let offsets = week.days.map(\.weekdayOffset).sorted()
            if Set(offsets).count != offsets.count {
                err("week.dupOffset", "Duplicate weekdayOffset within the week.", loc)
            }
            for off in offsets where !(0...6).contains(off) {
                err("week.badOffset", "weekdayOffset \(off) out of range 0…6.", loc)
            }

            var summedMinutes = 0
            for day in week.days {
                let dloc = "\(loc) / day \(day.weekdayOffset)"
                let expectedIndex = (week.weekNumber - 1) * 7 + day.weekdayOffset
                if day.dayIndex != expectedIndex {
                    err("day.index",
                        "dayIndex \(day.dayIndex) should be \(expectedIndex) for week \(week.weekNumber), offset \(day.weekdayOffset).",
                        dloc)
                }
                if !seenDayIndices.insert(day.dayIndex).inserted {
                    err("day.dupIndex", "Duplicate global dayIndex \(day.dayIndex).", dloc)
                }
                for workout in day.workouts {
                    summedMinutes += workout.plannedDurationMinutes
                    validateWorkout(workout, location: "\(dloc) / \(workout.title)", err: err, warn: warn)
                }
                validateBricks(day.workouts, location: dloc, err: err)
            }

            if week.plannedMinutes > 0, summedMinutes > 0 {
                let delta = abs(Double(week.plannedMinutes - summedMinutes)) / Double(week.plannedMinutes)
                if delta > plannedMinutesTolerance {
                    warn("week.minutesMismatch",
                         "Declared plannedMinutes (\(week.plannedMinutes)) is far from summed session minutes (\(summedMinutes)).",
                         loc)
                }
            }
        }

        // Global day-index completeness
        if seenDayIndices.count != plan.totalDays, plan.durationWeeks == plan.weeks.count {
            warn("plan.dayCoverage",
                 "Plan has \(seenDayIndices.count) day records; expected \(plan.totalDays). Some days may be missing.",
                 "plan")
        }

        return Result(issues: issues)
    }

    private func validatePhases(
        _ plan: TrainingPlanDefinition,
        err: (String, String, String) -> Void,
        warn: (String, String, String) -> Void
    ) {
        let sorted = plan.phases.sorted { $0.startWeek < $1.startWeek }
        var expectedNext = 1
        for phase in sorted {
            let loc = "phase '\(phase.name)'"
            if phase.startWeek > phase.endWeek {
                err("phase.range", "startWeek (\(phase.startWeek)) is after endWeek (\(phase.endWeek)).", loc)
            }
            if phase.startWeek != expectedNext {
                err("phase.gap",
                    "Phases must tile weeks with no gaps/overlaps; expected phase starting at week \(expectedNext) but got \(phase.startWeek).",
                    loc)
            }
            expectedNext = phase.endWeek + 1
        }
        if !sorted.isEmpty, expectedNext != plan.durationWeeks + 1 {
            warn("phase.coverage",
                 "Phases end at week \(expectedNext - 1) but the plan has \(plan.durationWeeks) weeks.",
                 "plan.phases")
        }
    }

    private func validateWorkout(
        _ w: WorkoutTemplate,
        location: String,
        err: (String, String, String) -> Void,
        warn: (String, String, String) -> Void
    ) {
        if !w.isOptional, w.plannedDurationMinutes <= 0 {
            err("workout.duration", "Non-optional workout must have a positive plannedDurationMinutes.", location)
        }
        if let d = w.plannedDistanceMeters, d < 0 {
            err("workout.distance", "plannedDistanceMeters cannot be negative.", location)
        }
        if let h = w.preferredHour, !(0...23).contains(h) {
            err("workout.hour", "preferredHour must be 0–23.", location)
        }
        if let m = w.preferredMinute, !(0...59).contains(m) {
            err("workout.minute", "preferredMinute must be 0–59.", location)
        }
        if w.isBrick && w.brickGroupID == nil {
            warn("workout.brickGroup", "Brick workout has no brickGroupID; it won't be grouped with its partner.", location)
        }
    }

    private func validateBricks(
        _ workouts: [WorkoutTemplate],
        location: String,
        err: (String, String, String) -> Void
    ) {
        let groups = Dictionary(grouping: workouts.filter { $0.brickGroupID != nil }, by: { $0.brickGroupID! })
        for (id, members) in groups where members.count < 2 {
            err("brick.incomplete",
                "Brick group \(id.uuidString.prefix(8)) has only \(members.count) member; a brick needs at least two linked sessions.",
                location)
        }
    }
}
