import Foundation

/// Deterministically generates the bundled 36‑week full‑distance plan.
///
/// Why a generator instead of hand‑written JSON: 252 days of sessions are far
/// more correct and maintainable as code with progression formulas than as a
/// hand‑typed blob — and the output is validated by `PlanValidator` in CI. The
/// executable `enduranceplan` encodes this to the JSON the app bundles; the app
/// itself only ever reads the JSON (never calls the generator at runtime).
///
/// Structure follows `TRAINING_SOURCES.md`: a long aerobic base, a progressive
/// build with weekly bricks, a recovery week every 4th week (≈3:1), a peak
/// simulation, then a volume‑cutting taper that retains some intensity. Long runs
/// are capped (~2.5 h) — no full‑marathon training run.
public enum PlanGenerator {

    public static let planID = UUIDv5.make(namespace: UUIDv5.Namespace.enduranceSchedule, name: "endurance-36wk-v1")

    // Recovery weeks (every 4th) and the special end‑of‑plan weeks.
    static let recoveryWeeks: Set<Int> = [4, 8, 12, 16, 20, 24, 28, 32]

    struct PhaseSpec { let name: String; let start: Int; let end: Int; let load: WeekLoad; let objective: String }
    static let phaseSpecs: [PhaseSpec] = [
        .init(name: "Foundation", start: 1, end: 4, load: .base, objective: "Establish routine, swim technique, and easy aerobic volume."),
        .init(name: "Base 1", start: 5, end: 8, load: .base, objective: "Grow aerobic endurance across all three disciplines."),
        .init(name: "Base 2", start: 9, end: 12, load: .base, objective: "Extend long sessions; introduce steady tempo."),
        .init(name: "Build 1", start: 13, end: 16, load: .build, objective: "Add threshold work and progressive weekend bricks."),
        .init(name: "Build 2", start: 17, end: 20, load: .build, objective: "Longer bricks; sustained race‑pace segments."),
        .init(name: "Endurance specificity", start: 21, end: 24, load: .build, objective: "Race‑duration long rides; fueling rehearsal."),
        .init(name: "Race‑specific build", start: 25, end: 28, load: .build, objective: "Race‑pace practice on tired legs; open‑water skills."),
        .init(name: "Peak", start: 29, end: 33, load: .peak, objective: "Highest specific volume and a final big simulation."),
        .init(name: "Taper", start: 34, end: 35, load: .taper, objective: "Cut volume, keep some intensity, arrive fresh."),
        .init(name: "Race week", start: 36, end: 36, load: .race, objective: "Rest, sharpen, prepare, and race."),
    ]

    public static func make36Week() -> TrainingPlanDefinition {
        var phases: [TrainingPhaseDefinition] = []
        for p in phaseSpecs {
            phases.append(TrainingPhaseDefinition(
                id: UUIDv5.make(namespace: UUIDv5.Namespace.enduranceSchedule, name: "phase:\(p.name)"),
                name: p.name, startWeek: p.start, endWeek: p.end, objective: p.objective, defaultLoad: p.load))
        }

        var weeks: [TrainingWeekDefinition] = []
        for w in 1...36 {
            weeks.append(makeWeek(w, phases: phases))
        }
        // Make step ids deterministic by position so the generated JSON is
        // byte-reproducible across runs (no git churn, and CI can assert the
        // committed file is in sync).
        for wi in weeks.indices {
            for di in weeks[wi].days.indices {
                for ti in weeks[wi].days[di].workouts.indices {
                    let tid = weeks[wi].days[di].workouts[ti].id.uuidString
                    weeks[wi].days[di].workouts[ti].warmup = canonicalize(weeks[wi].days[di].workouts[ti].warmup, base: "\(tid):wu")
                    weeks[wi].days[di].workouts[ti].mainSet = canonicalize(weeks[wi].days[di].workouts[ti].mainSet, base: "\(tid):ms")
                    weeks[wi].days[di].workouts[ti].cooldown = canonicalize(weeks[wi].days[di].workouts[ti].cooldown, base: "\(tid):cd")
                }
            }
        }

        return TrainingPlanDefinition(
            id: planID,
            schemaVersion: EnduranceDomain.currentPlanSchemaVersion,
            name: "36‑Week First Full‑Distance",
            summary: "A 36‑week plan for a first full‑distance triathlon. Goal: finish safely and consistently. Educational, not medical or coaching advice.",
            durationWeeks: 36,
            startWeekday: 2,
            phases: phases,
            weeks: weeks,
            metadata: PlanMetadata(
                author: "Endurance",
                version: "1.0.0",
                athleteLevel: "First‑timer, finish goal",
                goal: "Complete a full‑distance triathlon safely",
                createdISO8601: "2026-07-25T00:00:00Z",
                tags: ["full-distance", "first-timer", "finish", "36-week"],
                disclaimer: "This plan is educational and general. It is not medical advice or a substitute for a qualified coach or clinician. Stop and seek professional guidance for pain, illness, dizziness, chest symptoms, or unusual fatigue."))
    }

    /// Recursively assign deterministic ids to steps based on their position.
    static func canonicalize(_ steps: [WorkoutStep], base: String) -> [WorkoutStep] {
        steps.enumerated().map { (i, original) in
            var s = original
            s.id = UUIDv5.make(namespace: UUIDv5.Namespace.enduranceSchedule, name: "\(base):\(i)")
            s.childSteps = canonicalize(s.childSteps, base: "\(base):\(i)")
            return s
        }
    }

    // MARK: - Week

    static func phaseSpec(for week: Int) -> PhaseSpec { phaseSpecs.first { week >= $0.start && week <= $0.end }! }

    static func load(for week: Int) -> WeekLoad {
        if week == 36 { return .race }
        if week >= 34 { return .taper }
        if recoveryWeeks.contains(week) { return .recovery }
        return phaseSpec(for: week).load
    }

    /// A 0…1 volume factor that ramps up by phase, dips on recovery weeks, and
    /// tapers at the end. Drives session durations.
    static func volumeFactor(for week: Int) -> Double {
        if week == 36 { return 0.25 }
        if week == 35 { return 0.45 }
        if week == 34 { return 0.6 }
        if recoveryWeeks.contains(week) { return 0.6 }
        // Ramp 0.45 → 1.0 across weeks 1…33.
        let ramp = 0.45 + 0.55 * (Double(min(week, 33) - 1) / 32.0)
        return min(1.0, ramp)
    }

    static func makeWeek(_ w: Int, phases: [TrainingPhaseDefinition]) -> TrainingWeekDefinition {
        let spec = phaseSpec(for: w)
        let load = load(for: w)
        let phaseID = phases.first { $0.name == spec.name }!.id
        let isRecovery = (load == .recovery)

        let days: [TrainingDayDefinition]
        if w == 36 {
            days = raceWeekDays(w)
        } else {
            days = (0...6).map { makeDay(week: w, offset: $0, load: load, isRecovery: isRecovery) }
        }
        let minutes = days.flatMap { $0.workouts }.filter { !$0.isOptional }.reduce(0) { $0 + $1.plannedDurationMinutes }

        let title: String
        let objective: String
        if w == 36 { title = "Week 36 — Race week"; objective = "Rest, prepare your gear and race plan, and race." }
        else if isRecovery { title = "Week \(w) — Recovery"; objective = "Absorb the block. Keep it genuinely easy — this is where you get stronger." }
        else if load == .taper { title = "Week \(w) — Taper"; objective = "Lower volume, keep a little intensity, and arrive fresh." }
        else { title = "Week \(w) — \(spec.name)"; objective = spec.objective }

        return TrainingWeekDefinition(
            id: UUIDv5.make(namespace: UUIDv5.Namespace.enduranceSchedule, name: "week:\(w)"),
            weekNumber: w, phaseID: phaseID, title: title, objective: objective,
            load: load, plannedMinutes: minutes, days: days,
            coachNote: isRecovery ? "Resist the urge to add training this week." : nil)
    }

    // MARK: - Days (default weekly structure, brief §7)

    static func makeDay(week: Int, offset: Int, load: WeekLoad, isRecovery: Bool) -> TrainingDayDefinition {
        let dayIndex = (week - 1) * 7 + offset
        let vf = volumeFactor(for: week)
        var workouts: [WorkoutTemplate] = []

        switch offset {
        case 0: // Monday — recovery & technique
            workouts = [Sessions.mobility(week, offset, minutes: 30)]
        case 1: // Tuesday — quality bike (+ optional strength)
            workouts = [Sessions.bikeQuality(week, offset, load: load, vf: vf)]
            if !isRecovery && week <= 28 { workouts.append(Sessions.strength(week, offset, slot: 1)) }
        case 2: // Wednesday — swim endurance + easy run
            workouts = [
                Sessions.swimEndurance(week, offset, vf: vf),
                Sessions.runEasy(week, offset, slot: 1, vf: vf)
            ]
        case 3: // Thursday — quality run (+ optional strength)
            workouts = [Sessions.runQuality(week, offset, load: load, vf: vf)]
            if !isRecovery && week <= 24 { workouts.append(Sessions.strength(week, offset, slot: 1)) }
        case 4: // Friday — technique swim / recovery
            workouts = [Sessions.swimTechnique(week, offset, vf: vf)]
        case 5: // Saturday — long bike + brick run
            let brick = UUIDv5.make(namespace: UUIDv5.Namespace.enduranceSchedule, name: "brick:\(week)")
            workouts = [
                Sessions.bikeLong(week, offset, vf: vf, brick: brick),
                Sessions.brickRun(week, offset, slot: 1, vf: vf, brick: brick)
            ]
        case 6: // Sunday — long run (+ optional recovery swim)
            workouts = [Sessions.runLong(week, offset, vf: vf)]
            if week >= 9 && !isRecovery { workouts.append(Sessions.recoverySwim(week, offset, slot: 1)) }
        default: break
        }

        return TrainingDayDefinition(
            id: UUIDv5.make(namespace: UUIDv5.Namespace.enduranceSchedule, name: "day:\(week):\(offset)"),
            dayIndex: dayIndex, weekdayOffset: offset,
            title: dayTitle(offset), objective: dayObjective(offset, isRecovery: isRecovery),
            workouts: workouts,
            nutrition: offset == 5 || offset == 6 ? DayNutrition(summary: "Fuel earlier in the day and rehearse race‑day nutrition.") : nil,
            recovery: RecoveryGuidance(summary: "Prioritise sleep and easy movement.", prompts: ["Note soreness and energy", "Hydrate through the day"]))
    }

    static func dayTitle(_ o: Int) -> String {
        ["Recovery & technique", "Bike quality", "Swim + easy run", "Run quality", "Technique swim", "Long ride + brick", "Long run"][o]
    }
    static func dayObjective(_ o: Int, isRecovery: Bool) -> String {
        if isRecovery { return "Keep everything easy today." }
        return ["Loosen up and refine technique.", "Controlled quality on the bike.", "Aerobic swim and an easy run off it.",
                "Quality running; stay relaxed and tall.", "Short technique‑focused swim.",
                "The week's key aerobic session — steady and well‑fuelled.", "Time on feet at an easy, conversational effort."][o]
    }

    // MARK: - Race week

    static func raceWeekDays(_ week: Int) -> [TrainingDayDefinition] {
        func day(_ o: Int, _ title: String, _ obj: String, _ workouts: [WorkoutTemplate]) -> TrainingDayDefinition {
            TrainingDayDefinition(
                id: UUIDv5.make(namespace: UUIDv5.Namespace.enduranceSchedule, name: "day:\(week):\(o)"),
                dayIndex: (week - 1) * 7 + o, weekdayOffset: o, title: title, objective: obj, workouts: workouts,
                recovery: RecoveryGuidance(summary: "Rest, hydrate, and stay off your feet where you can."))
        }
        return [
            day(0, "Easy spin", "Loosen the legs.", [Sessions.bikeOpener(week, 0, minutes: 30)]),
            day(1, "Short swim", "Feel the water; nothing hard.", [Sessions.swimTechnique(week, 1, vf: 0.3)]),
            day(2, "Openers", "Short bike + run with a few brief pickups.", [Sessions.bikeOpener(week, 2, minutes: 30), Sessions.runEasy(week, 2, slot: 1, vf: 0.3)]),
            day(3, "Rest & prepare", "Full rest. Check gear and race plan.", []),
            day(4, "Travel / shakeout", "Optional very short swim if you have water access.", [Sessions.recoverySwim(week, 4, slot: 0, optional: true)]),
            day(5, "Pre‑race", "Short spin with 2–3 short openers. Rack bike, lay out bags.", [Sessions.bikeOpener(week, 5, minutes: 20)]),
            day(6, "Race day", "Race your plan. Fuel early and often; stay within yourself, especially on the bike.", [Sessions.raceDay(week, 6)]),
        ]
    }
}
