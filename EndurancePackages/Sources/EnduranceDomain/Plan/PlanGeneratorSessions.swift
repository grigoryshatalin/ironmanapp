import Foundation

/// Session builders for `PlanGenerator`. Each produces a fully actionable
/// `WorkoutTemplate` with structured warm‑up / main set / cool‑down, cues, and —
/// for long sessions — configurable fueling and safety guidance.
enum Sessions {

    static func id(_ week: Int, _ offset: Int, _ slot: Int) -> UUID {
        UUIDv5.make(namespace: UUIDv5.Namespace.enduranceSchedule, name: "tmpl:\(week):\(offset):\(slot)")
    }
    static func clamp(_ v: Int, _ lo: Int, _ hi: Int) -> Int { min(hi, max(lo, v)) }
    static func round50(_ m: Double) -> Double { (m / 50).rounded() * 50 }

    /// - Parameter sec: seconds, for steps shorter than a minute. The helper
    ///   originally took whole minutes only, so a 20-second rest could not be
    ///   expressed and was written as `min: 0` with the real duration left in the
    ///   label text. That produced a step with no goal WorkoutKit could convert,
    ///   which refused the whole session — 35 swims never reached the Watch.
    static func step(_ kind: StepKind, _ label: String, min: Int? = nil, sec: Int? = nil, m: Double? = nil, z: IntensityZone? = nil, reps: Int = 1, children: [WorkoutStep] = [], note: String? = nil) -> WorkoutStep {
        let seconds = sec ?? min.map { $0 * 60 }
        return WorkoutStep(kind: kind, label: label, durationSeconds: seconds, distanceMeters: m, intensity: z, repeats: reps, childSteps: children, note: note)
    }

    // MARK: Swim

    static func swimEndurance(_ w: Int, _ o: Int, vf: Double) -> WorkoutTemplate {
        let minutes = clamp(Int(40 + 35 * vf), 40, 75)
        let distance = round50(Double(minutes) * 45)
        let reps = clamp(Int(4 + 6 * vf), 4, 10)
        return WorkoutTemplate(
            id: id(w, o, 0), sport: .swim, title: "Swim endurance", objective: "Steady aerobic swimming with relaxed form.",
            plannedDurationMinutes: minutes, plannedDistanceMeters: distance, intensity: .endurance, stressCategory: .moderate,
            warmup: [step(.warmup, "Easy swim", min: 6, z: .recovery), step(.drill, "Drills", min: 4, note: "Catch‑up + single‑arm")],
            mainSet: [step(.work, "\(reps) × 100 steady", z: .endurance, reps: reps, children: [step(.work, "100 steady", m: 100, z: .endurance), step(.recovery, "20 s rest", sec: 20)])],
            cooldown: [step(.cooldown, "Easy swim", min: 5, z: .recovery)],
            techniqueCues: ["High‑elbow catch", "Exhale steadily underwater", "Long, relaxed stroke — count strokes per length"])
    }

    static func swimTechnique(_ w: Int, _ o: Int, vf: Double) -> WorkoutTemplate {
        let minutes = clamp(Int(30 + 15 * vf), 25, 45)
        let distance = round50(Double(minutes) * 38)
        return WorkoutTemplate(
            id: id(w, o, 0), sport: .swim, title: "Technique swim", objective: "Short, technique‑focused swim — quality over volume.",
            plannedDurationMinutes: minutes, plannedDistanceMeters: distance, intensity: .recovery, stressCategory: .recovery,
            warmup: [step(.warmup, "Easy swim", min: 5, z: .recovery)],
            mainSet: [step(.drill, "6 × 50 drill/swim", reps: 6, children: [step(.drill, "25 drill", m: 25), step(.work, "25 swim", m: 25, z: .endurance)])],
            cooldown: [step(.cooldown, "Easy swim", min: 4, z: .recovery)],
            techniqueCues: ["Pick one focus per length", "Balance and a steady kick", "Bilateral breathing if you can"])
    }

    static func recoverySwim(_ w: Int, _ o: Int, slot: Int, optional: Bool = true) -> WorkoutTemplate {
        WorkoutTemplate(
            id: id(w, o, slot), sport: .swim, title: "Recovery swim", objective: "Loosen up with very easy swimming.",
            plannedDurationMinutes: 25, plannedDistanceMeters: 900, intensity: .recovery, stressCategory: .recovery, order: slot,
            warmup: [], mainSet: [step(.steady, "Easy continuous swim", min: 20, z: .recovery)], cooldown: [],
            techniqueCues: ["Nothing hard — just feel the water"], isOptional: optional)
    }

    // MARK: Bike

    static func bikeQuality(_ w: Int, _ o: Int, load: WeekLoad, vf: Double) -> WorkoutTemplate {
        let minutes = clamp(Int(50 + 30 * vf), 50, 85)
        let recovery = (load == .recovery)
        let zone: IntensityZone = recovery ? .tempo : (w >= 17 ? .threshold : .tempo)
        let reps = recovery ? 3 : clamp(Int(3 + 3 * vf), 3, 6)
        return WorkoutTemplate(
            id: id(w, o, 0), sport: .bike, title: recovery ? "Bike steady" : "Bike intervals",
            objective: recovery ? "Controlled steady riding." : "Sustained efforts to lift your durable power.",
            plannedDurationMinutes: minutes, plannedDistanceMeters: round50(Double(minutes) / 60 * 28000),
            intensity: zone, stressCategory: recovery ? .moderate : .hard,
            warmup: [step(.warmup, "Easy spin", min: 12, z: .endurance)],
            mainSet: recovery
                ? [step(.steady, "Steady aerobic", min: minutes - 20, z: .tempo)]
                : [step(.work, "\(reps) × 6 min", reps: reps, children: [step(.work, "6 min", min: 6, z: zone), step(.recovery, "3 min easy", min: 3, z: .recovery)])],
            cooldown: [step(.cooldown, "Easy spin", min: 8, z: .recovery)],
            techniqueCues: ["Smooth, round pedal stroke", "Relax shoulders and hands", "Hold cadence 85–95 rpm"],
            gear: ["Bike computer charged", "Two bottles"])
    }

    static func bikeLong(_ w: Int, _ o: Int, vf: Double, brick: UUID) -> WorkoutTemplate {
        let minutes = clamp(Int(90 + 260 * vf), 90, 350)
        let key = minutes >= 150
        return WorkoutTemplate(
            id: id(w, o, 0), sport: .bike, title: "Long ride", objective: "The week's aerobic cornerstone — steady, well‑fuelled time in the saddle.",
            plannedDurationMinutes: minutes, plannedDistanceMeters: round50(Double(minutes) / 60 * 28000),
            intensity: .endurance, stressCategory: .long, order: 0,
            warmup: [step(.warmup, "Ease in", min: 15, z: .recovery)],
            mainSet: [
                step(.steady, "Steady endurance", min: minutes - 25, z: .endurance, note: w >= 17 ? "Include 2–3 × 10 min at tempo if feeling good." : nil),
            ],
            cooldown: [step(.cooldown, "Spin down", min: 10, z: .recovery)],
            techniqueCues: ["Eat and drink on a schedule from the start", "Stay aero but comfortable", "Keep it controlled — this is not a race"],
            fueling: FuelingGuidance(carbsGramsPerHourLow: minutes >= 150 ? 60 : 30, carbsGramsPerHourHigh: minutes >= 150 ? 90 : 60,
                                     note: "Practice exactly what you plan to use on race day.", isKeyFuelingSession: key),
            hydration: HydrationGuidance(fluidsMillilitresPerHourLow: 500, fluidsMillilitresPerHourHigh: 750, note: "Drink to thirst; don't overdrink."),
            gear: ["Spare tube, tyre levers, pump/CO₂", "ID + phone", "Enough fuel for the whole ride"],
            safetyNotes: ["Tell someone your route and expected return", "Ride predictably in traffic", "Carry a way to call for help"],
            isBrick: true, brickGroupID: brick)
    }

    static func brickRun(_ w: Int, _ o: Int, slot: Int, vf: Double, brick: UUID) -> WorkoutTemplate {
        let minutes = clamp(Int(12 + 25 * vf), 12, 40)
        return WorkoutTemplate(
            id: id(w, o, slot), sport: .run, title: "Brick run", objective: "Run off the bike to adapt to heavy legs and lock in transition habits.",
            plannedDurationMinutes: minutes, plannedDistanceMeters: round50(Double(minutes) / 60 * 9500),
            intensity: .tempo, stressCategory: .moderate, order: slot,
            warmup: [], mainSet: [step(.transition, "Quick transition", min: 0, note: "Rack bike, change shoes, go."),
                                  step(.steady, "Run steady", min: minutes, z: .tempo, note: "Legs feel odd for the first few minutes — that's normal.")],
            cooldown: [], techniqueCues: ["Quick, light cadence off the bike", "Settle breathing early"],
            isBrick: true, brickGroupID: brick)
    }

    static func bikeOpener(_ w: Int, _ o: Int, minutes: Int) -> WorkoutTemplate {
        WorkoutTemplate(
            id: id(w, o, 0), sport: .bike, title: "Easy spin + openers", objective: "Stay loose and sharp without fatigue.",
            plannedDurationMinutes: minutes, plannedDistanceMeters: round50(Double(minutes) / 60 * 26000),
            intensity: .recovery, stressCategory: .easy,
            warmup: [step(.warmup, "Easy spin", min: minutes - 6, z: .recovery)],
            mainSet: [step(.work, "3 × 1 min build", reps: 3, children: [step(.work, "1 min build to race effort", min: 1, z: .raceEffort), step(.recovery, "2 min easy", min: 2, z: .recovery)])],
            cooldown: [], techniqueCues: ["Short and snappy — nothing draining"])
    }

    // MARK: Run

    static func runEasy(_ w: Int, _ o: Int, slot: Int, vf: Double) -> WorkoutTemplate {
        let minutes = clamp(Int(25 + 20 * vf), 20, 45)
        return WorkoutTemplate(
            id: id(w, o, slot), sport: .run, title: "Easy run", objective: "Relaxed aerobic running at a conversational effort.",
            plannedDurationMinutes: minutes, plannedDistanceMeters: round50(Double(minutes) / 60 * 9500),
            intensity: .endurance, stressCategory: .easy, order: slot,
            mainSet: [step(.steady, "Easy run", min: minutes, z: .endurance)],
            techniqueCues: ["Tall posture, relaxed arms", "Light, quick steps"])
    }

    static func runQuality(_ w: Int, _ o: Int, load: WeekLoad, vf: Double) -> WorkoutTemplate {
        let minutes = clamp(Int(40 + 25 * vf), 40, 70)
        let recovery = (load == .recovery)
        let reps = recovery ? 3 : clamp(Int(3 + 3 * vf), 3, 6)
        let zone: IntensityZone = recovery ? .tempo : .threshold
        return WorkoutTemplate(
            id: id(w, o, 0), sport: .run, title: recovery ? "Run steady" : "Run threshold",
            objective: recovery ? "Steady controlled running." : "Threshold repeats to raise sustainable pace.",
            plannedDurationMinutes: minutes, plannedDistanceMeters: round50(Double(minutes) / 60 * 10000),
            intensity: zone, stressCategory: recovery ? .moderate : .hard,
            warmup: [step(.warmup, "Easy jog", min: 12, z: .endurance), step(.drill, "Strides", min: 3, note: "4 × 20 s relaxed")],
            mainSet: recovery
                ? [step(.steady, "Steady", min: minutes - 20, z: .tempo)]
                : [step(.work, "\(reps) × 5 min", reps: reps, children: [step(.work, "5 min", min: 5, z: zone), step(.recovery, "2 min jog", min: 2, z: .recovery)])],
            cooldown: [step(.cooldown, "Easy jog", min: 8, z: .recovery)],
            techniqueCues: ["Stay tall and relaxed at pace", "Even effort, not even splits"])
    }

    static func runLong(_ w: Int, _ o: Int, vf: Double) -> WorkoutTemplate {
        // Long run capped ~150 min (~2.5 h) — no full‑marathon training run.
        let minutes = clamp(Int(50 + 100 * vf), 45, 150)
        let key = minutes >= 90
        return WorkoutTemplate(
            id: id(w, o, 0), sport: .run, title: "Long run", objective: "Build durability with easy time on feet — never a full marathon in training.",
            plannedDurationMinutes: minutes, plannedDistanceMeters: round50(Double(minutes) / 60 * 9500),
            intensity: .endurance, stressCategory: .long,
            warmup: [], mainSet: [step(.steady, "Easy long run", min: minutes, z: .endurance, note: w >= 21 ? "Optional: last 15 min at steady race effort." : nil)],
            cooldown: [step(.cooldown, "Walk", min: 5, note: "Walk and rehydrate.")],
            techniqueCues: ["Keep it easy — you should be able to talk", "Practice race‑day fuel and drink"],
            fueling: FuelingGuidance(carbsGramsPerHourLow: 30, carbsGramsPerHourHigh: 60, note: "Rehearse race‑day fueling on runs over ~75 min.", isKeyFuelingSession: key),
            hydration: HydrationGuidance(fluidsMillilitresPerHourLow: 400, fluidsMillilitresPerHourHigh: 700, note: "Drink to thirst."),
            safetyNotes: ["Carry ID and a phone on long runs", "Plan a route with water and bail‑out points"])
    }

    // MARK: Strength / mobility

    static func strength(_ w: Int, _ o: Int, slot: Int) -> WorkoutTemplate {
        WorkoutTemplate(
            id: id(w, o, slot), sport: .strength, title: "Strength (optional)", objective: "General strength and injury resilience.",
            plannedDurationMinutes: 30, intensity: .tempo, stressCategory: .moderate, order: slot,
            mainSet: [step(.work, "Full‑body circuit", min: 25, note: "Squat, hinge, push, pull, core. Controlled reps.")],
            techniqueCues: ["Quality reps over load", "Stop 1–2 reps short of failure"],
            gear: ["Mat"], isOptional: true)
    }

    static func mobility(_ w: Int, _ o: Int, minutes: Int) -> WorkoutTemplate {
        WorkoutTemplate(
            id: id(w, o, 0), sport: .mobility, title: "Mobility & technique", objective: "Gentle mobility and easy movement to start the week.",
            plannedDurationMinutes: minutes, intensity: .recovery, stressCategory: .recovery,
            mainSet: [step(.steady, "Mobility flow", min: minutes, note: "Hips, ankles, thoracic spine; easy walk if you like.")],
            techniqueCues: ["Move slowly and breathe", "No pain — ease off if anything pinches"])
    }

    // MARK: Race

    static func raceDay(_ w: Int, _ o: Int) -> WorkoutTemplate {
        WorkoutTemplate(
            id: id(w, o, 0), sport: .race, title: "Race day", objective: "Full‑distance triathlon. Execute your plan and finish safely.",
            plannedDurationMinutes: 780, plannedDistanceMeters: 226_000, intensity: .raceEffort, stressCategory: .raceSpecific,
            mainSet: [
                step(.steady, "Swim 3.8 km", m: 3800, z: .endurance, note: "Start controlled; find clear water and sight regularly."),
                step(.transition, "T1", min: 0),
                step(.steady, "Bike 180 km", m: 180_000, z: .endurance, note: "Ride well within yourself — protect the run."),
                step(.transition, "T2", min: 0),
                step(.steady, "Run 42.2 km", m: 42_200, z: .endurance, note: "Run/walk aid stations as needed; keep fuelling."),
            ],
            techniqueCues: ["Fuel early and often", "Nothing new on race day", "Break it into small, manageable pieces"],
            fueling: FuelingGuidance(carbsGramsPerHourLow: 60, carbsGramsPerHourHigh: 90, note: "Exactly what you practiced.", isKeyFuelingSession: true),
            hydration: HydrationGuidance(fluidsMillilitresPerHourLow: 500, fluidsMillilitresPerHourHigh: 750, note: "Drink to thirst; take on electrolytes; do not overdrink."),
            gear: ["Wetsuit (if permitted)", "Timing chip", "Race nutrition", "Bike checked the day before"],
            safetyNotes: ["Obey marshals and cut‑off times", "Stop and seek help for chest pain, dizziness, or unusual symptoms", "It is always OK to stop"])
    }
}
