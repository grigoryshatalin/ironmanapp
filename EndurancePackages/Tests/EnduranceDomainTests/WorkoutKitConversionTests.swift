import Testing
import Foundation
@testable import EnduranceDomain

/// §I — WorkoutKit conversion.
///
/// The contract that matters is fidelity honesty: a conversion may be `exact`,
/// `simplified`, or `unsupported`, and it must never *quietly* drop a step, a
/// target, or a transition. Most of these tests therefore assert what the
/// converter refuses to claim, not just what it produces.
@Suite("WorkoutKit conversion")
struct WorkoutKitConversionTests {

    private let converter = WorkoutKitConverter()

    // MARK: - Fixtures

    private func step(
        kind: StepKind = .work,
        label: String = "Step",
        seconds: Int? = 600,
        metres: Double? = nil,
        open: Bool = false,
        intensity: IntensityZone? = nil,
        target: WorkoutTarget? = nil,
        repeats: Int = 1,
        children: [WorkoutStep] = []
    ) -> WorkoutStep {
        WorkoutStep(
            kind: kind,
            label: label,
            durationSeconds: seconds,
            distanceMeters: metres,
            isOpenGoal: open,
            intensity: intensity,
            target: target,
            repeats: repeats,
            childSteps: children)
    }

    private func template(
        sport: Sport = .run,
        warmup: [WorkoutStep] = [],
        mainSet: [WorkoutStep] = [],
        cooldown: [WorkoutStep] = [],
        cues: [String] = [],
        gear: [String] = [],
        safety: [String] = [],
        fueling: FuelingGuidance? = nil,
        location: WorkoutLocation? = nil,
        isBrick: Bool = false
    ) -> WorkoutTemplate {
        WorkoutTemplate(
            sport: sport,
            title: "Session",
            objective: "Objective",
            plannedDurationMinutes: 60,
            intensity: .endurance,
            stressCategory: .moderate,
            workoutLocation: location,
            warmup: warmup,
            mainSet: mainSet,
            cooldown: cooldown,
            techniqueCues: cues,
            fueling: fueling,
            gear: gear,
            safetyNotes: safety,
            isBrick: isBrick)
    }

    private func scheduled(
        sport: Sport = .run,
        minutes: Int = 60,
        distance: Double? = nil,
        reduced: Int? = nil,
        isBrick: Bool = false,
        title: String = "Session"
    ) -> ScheduledWorkout {
        var workout = ScheduledFactory.make(
            name: title,
            sport: sport,
            stress: .moderate,
            start: Date(timeIntervalSince1970: 1_770_000_000),
            durationMinutes: minutes,
            distanceMeters: distance)
        workout.reducedDurationMinutes = reduced
        workout.isBrick = isBrick
        return workout
    }

    // MARK: - Exact

    @Test("A plain session with no structure and no extras converts exactly")
    func plainSessionIsExact() {
        let result = converter.convert(scheduled(distance: 10_000), template: template())

        #expect(result.outcome == .exact)
        #expect(result.warnings.isEmpty)
        #expect(result.automaticSchedulingAllowed, "an exact conversion may schedule without asking")
        #expect(!result.requiresUserConfirmation)

        guard case .singleGoal(let activity, _, let goal) = result.representation else {
            Issue.record("expected a single-goal representation, got \(String(describing: result.representation))")
            return
        }
        #expect(activity == .running)
        #expect(goal == .distance(metres: 10_000))
    }

    @Test("Distance is preferred over time when the plan states one")
    func distanceGoalPreferred() {
        let result = converter.convert(scheduled(minutes: 45, distance: 8000), template: template())
        guard case .singleGoal(_, _, let goal) = result.representation else { return }
        #expect(goal == .distance(metres: 8000))
    }

    @Test("Without a distance the goal falls back to planned time")
    func timeGoalFallback() {
        let result = converter.convert(scheduled(minutes: 45), template: template())
        guard case .singleGoal(_, _, let goal) = result.representation else { return }
        #expect(goal == .time(seconds: 45 * 60))
    }

    @Test("A structured interval session with no lost content is exact")
    func structuredIntervalsAreExact() {
        let block = step(kind: .work, label: "Rep", seconds: 360, repeats: 4, children: [
            step(kind: .work, label: "Hard", seconds: 360),
            step(kind: .recovery, label: "Easy", seconds: 180),
        ])
        let result = converter.convert(
            scheduled(),
            template: template(warmup: [step(kind: .warmup, seconds: 600)],
                               mainSet: [block],
                               cooldown: [step(kind: .cooldown, seconds: 600)]))

        #expect(result.outcome == .exact)
        #expect(result.warnings.isEmpty)

        guard case .custom(_, _, _, let warmup, let blocks, let cooldown) = result.representation else {
            Issue.record("expected a custom representation")
            return
        }
        #expect(warmup != nil)
        #expect(cooldown != nil)
        #expect(blocks.count == 1)
        #expect(blocks.first?.iterations == 4, "repeats must survive as iterations, not be flattened")
        #expect(blocks.first?.steps.count == 2)
    }

    @Test("Recovery children are marked as recovery, not work")
    func recoveryPurposeIsPreserved() {
        let block = step(kind: .work, repeats: 3, children: [
            step(kind: .work, seconds: 120),
            step(kind: .recovery, seconds: 60),
        ])
        let result = converter.convert(scheduled(), template: template(mainSet: [block]))
        guard case .custom(_, _, _, _, let blocks, _) = result.representation else { return }
        #expect(blocks.first?.steps.map(\.purpose) == [.work, .recovery])
    }

    // MARK: - Simplified, with disclosure

    /// Supplemental content is disclosed but does not gate scheduling: the
    /// intervals, goals and targets all transfer, so the session performed on
    /// the Watch *is* the planned session.
    @Test("Technique cues are disclosed but still schedule automatically")
    func techniqueCuesDisclosedWithoutBlocking() {
        let result = converter.convert(scheduled(), template: template(cues: ["High elbow catch"]))
        #expect(result.warnings.contains(.techniqueCuesRemainInEndurance))
        #expect(result.outcome == .exact)
        #expect(result.automaticSchedulingAllowed,
                "supplemental prose staying behind is not a change to the workout")
        #expect(!result.requiresUserConfirmation)
    }

    @Test("Supplemental warnings are marked non-structural; structural ones are not")
    func warningClassification() {
        for warning: WorkoutKitConversionWarning in [
            .techniqueCuesRemainInEndurance, .fuelingInstructionsRemainInEndurance,
            .supplementalInstructionsRemainInEndurance, .rpePreservedAsText,
        ] {
            #expect(!warning.isStructural, "\(warning) does not change the workout")
        }
        for warning: WorkoutKitConversionWarning in [
            .stepsCombined, .nestedRepetitionsFlattened, .shortenedWorkoutUsesSingleGoal,
            .transitionInstructionsOmitted, .drillRepresentedAsWork,
        ] {
            #expect(warning.isStructural, "\(warning) changes what gets trained")
        }
    }

    @Test("Fueling guidance is disclosed rather than silently dropped")
    func fuelingDisclosed() {
        let fueling = FuelingGuidance(carbsGramsPerHourLow: 60, carbsGramsPerHourHigh: 90)
        let result = converter.convert(scheduled(), template: template(fueling: fueling))
        #expect(result.warnings.contains(.fuelingInstructionsRemainInEndurance))
    }

    @Test("Gear and safety notes are disclosed")
    func gearAndSafetyDisclosed() {
        let result = converter.convert(
            scheduled(), template: template(gear: ["Wetsuit"], safety: ["Swim with a buddy"]))
        #expect(result.warnings.contains(.supplementalInstructionsRemainInEndurance))
        #expect(result.outcome == .exact, "a gear list is not a change to the session")
    }

    @Test("A structural change does require confirmation")
    func structuralChangeRequiresConfirmation() {
        let result = converter.convert(
            scheduled(),
            template: template(
                warmup: [step(kind: .warmup, seconds: 300), step(kind: .warmup, seconds: 300)],
                mainSet: [step(kind: .steady, seconds: 1800)]))
        #expect(result.outcome == .simplified)
        #expect(result.requiresUserConfirmation)
        #expect(!result.automaticSchedulingAllowed)
    }

    /// The important one: a shortened session must not leave the original, longer
    /// intervals sitting on the Watch.
    @Test("A shortened session becomes a truthful single goal, explicitly disclosed")
    func shortenedSessionCollapsesToSingleGoal() {
        let block = step(kind: .work, repeats: 6, children: [step(kind: .work, seconds: 300)])
        let result = converter.convert(
            scheduled(minutes: 90, reduced: 40),
            template: template(mainSet: [block]))

        #expect(result.outcome == .simplified)
        #expect(result.warnings.contains(.shortenedWorkoutUsesSingleGoal))

        guard case .singleGoal(_, _, let goal) = result.representation else {
            Issue.record("a shortened session must not keep its original interval structure")
            return
        }
        #expect(goal == .time(seconds: 40 * 60), "the goal must reflect the shortened duration")
    }

    @Test("RPE-only guidance is preserved as text, never invented as a sensor alert")
    func rpeIsTextNotAnAlert() {
        let result = converter.convert(
            scheduled(),
            template: template(mainSet: [step(kind: .steady, seconds: 1800, intensity: .tempo)]))

        #expect(result.warnings.contains(.rpePreservedAsText))
        guard case .custom(_, _, _, _, let blocks, _) = result.representation else { return }
        let converted = blocks.first?.steps.first
        #expect(converted?.alert == nil, "an RPE zone must never become a fabricated alert")
        #expect(converted?.perceivedExertionRange != nil)
    }

    @Test("A drill is represented as work, and that is disclosed")
    func drillIsDisclosed() {
        let result = converter.convert(
            scheduled(sport: .swim),
            template: template(sport: .swim, mainSet: [step(kind: .drill, seconds: nil, metres: 200)]))
        #expect(result.warnings.contains(.drillRepresentedAsWork))
    }

    @Test("Combining several warm-up steps is disclosed")
    func combinedStepsDisclosed() {
        let result = converter.convert(
            scheduled(),
            template: template(
                warmup: [step(kind: .warmup, seconds: 300), step(kind: .warmup, seconds: 300)],
                mainSet: [step(kind: .steady, seconds: 1800)]))
        #expect(result.warnings.contains(.stepsCombined))
        guard case .custom(_, _, _, let warmup, _, _) = result.representation else { return }
        #expect(warmup?.goal == .time(seconds: 600), "combined duration must be the sum")
    }

    // MARK: - Explicit refusals

    @Test("A brick is refused — it needs linked components, not one activity")
    func brickIsUnsupported() {
        let result = converter.convert(scheduled(isBrick: true), template: template())
        #expect(result.outcome == .unsupported)
        #expect(result.unsupportedReasons == [.brickRequiresLinkedComponents])
        #expect(result.representation == nil)
        #expect(!result.automaticSchedulingAllowed)
    }

    @Test("A race is refused — it needs structured multisport")
    func raceIsUnsupported() {
        let result = converter.convert(scheduled(sport: .race), template: template(sport: .race))
        #expect(result.outcome == .unsupported)
        #expect(result.unsupportedReasons == [.raceRequiresStructuredMultisport])
    }

    @Test("Sports WorkoutKit cannot express are refused, not approximated")
    func unsupportedSportsRefused() {
        // Only recovery remains. Strength is filed as HIIT and mobility by its
        // own shape — both considered approximations, because the alternative
        // was that those sessions never reached the Watch at all. Recovery is
        // walking or nothing, and has no structure worth sending.
        for sport in [Sport.recovery] {
            let result = converter.convert(scheduled(sport: sport), template: template(sport: sport))
            #expect(result.outcome == .unsupported, "\(sport)")
            #expect(result.unsupportedReasons == [.unsupportedSport], "\(sport)")
        }
    }

    @Test("Continuous mobility is scheduled as functional strength training")
    func continuousMobilityMapsToFunctionalStrength() {
        let result = converter.convert(scheduled(sport: .mobility), template: template(sport: .mobility))
        #expect(result.outcome.isSchedulable)
        if case .custom(let activity, _, _, _, _, _) = result.representation {
            #expect(activity == .functionalStrengthTraining,
                    "a thirty-minute mobility flow is not interval training")
        } else if case .singleGoal(let activity, _, _) = result.representation {
            #expect(activity == .functionalStrengthTraining)
        } else {
            Issue.record("mobility should convert to a schedulable representation")
        }
    }

    @Test("Mobility built as a circuit is scheduled as interval training")
    func circuitMobilityMapsToHIIT() {
        // The branch that exists for coach-authored plans (§28.12): repeated
        // work with recovery genuinely behaves like interval training.
        let circuit = WorkoutTemplate(
            id: UUID(), sport: .mobility, title: "Mobility circuit",
            objective: "Circuit", plannedDurationMinutes: 30,
            plannedDistanceMeters: nil, intensity: .endurance, stressCategory: .easy,
            warmup: [],
            mainSet: [
                WorkoutStep(kind: .work, label: "Round", durationSeconds: 60, repeats: 4),
                WorkoutStep(kind: .work, label: "Round two", durationSeconds: 60, repeats: 4),
            ],
            cooldown: [])
        #expect(WorkoutKitConverter.mobilityActivity(for: circuit) == .highIntensityIntervalTraining)
    }

    @Test("Strength is scheduled as high-intensity interval training")
    func strengthMapsToHIIT() {
        let result = converter.convert(scheduled(sport: .strength), template: template(sport: .strength))
        #expect(result.outcome.isSchedulable)
        #expect(result.unsupportedReasons.isEmpty)
        #expect(result.representation != nil,
                "a schedulable conversion must carry a representation to send")
    }

    @Test("A missing template is refused rather than guessed at")
    func missingTemplateRefused() {
        let result = converter.convert(scheduled(), template: nil)
        #expect(result.outcome == .unsupported)
        #expect(result.unsupportedReasons == [.missingTemplate])
    }

    @Test("Nested repetitions are refused rather than silently flattened")
    func nestedRepetitionsRefused() {
        let grandchild = step(kind: .work, seconds: 60)
        let child = step(kind: .work, seconds: 120, repeats: 2, children: [grandchild])
        let outer = step(kind: .work, repeats: 3, children: [child])

        let result = converter.convert(scheduled(), template: template(mainSet: [outer]))
        #expect(result.outcome == .unsupported)
        #expect(result.unsupportedReasons == [.nestedRepetitions],
                "flattening a nested block would change the session the athlete trains")
    }

    @Test("A transition step makes the structure unrepresentable, and says so")
    func transitionRefused() {
        let result = converter.convert(
            scheduled(),
            template: template(mainSet: [step(kind: .transition, label: "T1", seconds: 120)]))
        #expect(result.outcome == .unsupported)
        #expect(result.unsupportedReasons == [.invalidWorkoutStructure])
        #expect(result.warnings.contains(.transitionInstructionsOmitted))
    }

    @Test("A step with no goal at all is unrepresentable")
    func goallessStepRefused() {
        let result = converter.convert(
            scheduled(),
            template: template(mainSet: [step(seconds: nil, metres: nil, open: false)]))
        #expect(result.outcome == .unsupported)
    }

    // MARK: - Goals and alerts

    @Test("A pool swim with distance and time uses the pool goal")
    func poolSwimGoal() {
        let result = converter.convert(
            scheduled(sport: .swim),
            template: template(sport: .swim,
                               mainSet: [step(kind: .work, seconds: 120, metres: 100)],
                               location: .pool))
        guard case .custom(_, let location, _, _, let blocks, _) = result.representation else {
            Issue.record("expected custom representation")
            return
        }
        #expect(location == .pool)
        #expect(blocks.first?.steps.first?.goal == .poolDistanceWithTime(metres: 100, seconds: 120))
    }

    @Test("An open-water swim does not use the pool goal")
    func openWaterNotPoolGoal() {
        let result = converter.convert(
            scheduled(sport: .swim),
            template: template(sport: .swim,
                               mainSet: [step(kind: .work, seconds: 120, metres: 100)],
                               location: .openWater))
        guard case .custom(_, _, _, _, let blocks, _) = result.representation else { return }
        #expect(blocks.first?.steps.first?.goal == .distance(metres: 100))
    }

    @Test("An unknown location stays unknown rather than being guessed")
    func unknownLocationStaysUnknown() {
        let result = converter.convert(scheduled(), template: template())
        guard case .singleGoal(_, let location, _) = result.representation else { return }
        #expect(location == .unknown)
    }

    @Test("Every explicit target maps to the matching alert")
    func targetsMapToAlerts() {
        let cases: [(WorkoutTarget, WorkoutKitAlertRepresentation)] = [
            (.heartRate(bpm: 140...155), .heartRate(bpm: 140...155)),
            (.power(watts: 200...240), .power(watts: 200...240)),
            (.cadence(rpm: 85...95), .cadence(rpm: 85...95)),
            (.speed(metresPerSecond: 3.0...3.5), .speed(metresPerSecond: 3.0...3.5)),
        ]
        for (target, expected) in cases {
            let result = converter.convert(
                scheduled(sport: .bike),
                template: template(sport: .bike,
                                   mainSet: [step(kind: .work, seconds: 600, target: target)]))
            guard case .custom(_, _, _, _, let blocks, _) = result.representation else {
                Issue.record("expected custom for \(target)")
                continue
            }
            #expect(blocks.first?.steps.first?.alert == expected)
        }
    }

    // MARK: - Result contract

    @Test("Explanation keys are catalog keys, never English copy")
    func explanationKeysAreCatalogKeys() {
        let result = converter.convert(scheduled(), template: template(cues: ["Cue"]))
        #expect(!result.explanationKeys.isEmpty)
        #expect(result.explanationKeys.allSatisfy { $0.hasPrefix("workoutkit.") },
                "framework-free code must not manufacture user-facing English")
    }

    @Test("The fingerprint is stable across identical conversions")
    func fingerprintIsStable() {
        let workout = scheduled()
        let t = template(cues: ["Cue"])
        let a = converter.convert(workout, template: t)
        let b = converter.convert(workout, template: t)
        #expect(a.fingerprint == b.fingerprint, "a stable fingerprint gates a previous approval")
        #expect(a.id != b.id, "the record id is per-conversion and must not be in the fingerprint")
    }

    @Test("The fingerprint changes when fidelity changes")
    func fingerprintTracksFidelity() {
        let workout = scheduled()
        let clean = converter.convert(workout, template: template())
        let lossy = converter.convert(workout, template: template(cues: ["Cue"]))
        #expect(clean.fingerprint != lossy.fingerprint,
                "a previously approved simplification must not silently cover a different one")
    }

    @Test("Only exact conversions may be scheduled automatically")
    func automaticSchedulingIsExactOnly() {
        #expect(WorkoutKitConversionOutcome.exact.isSchedulable)
        #expect(WorkoutKitConversionOutcome.simplified.isSchedulable)
        #expect(!WorkoutKitConversionOutcome.unsupported.isSchedulable)
        #expect(WorkoutKitConversionOutcome.simplified.requiresConfirmation)
        #expect(!WorkoutKitConversionOutcome.exact.requiresConfirmation)
    }

    @Test("A conversion result round-trips through Codable")
    func resultRoundTrips() throws {
        let result = converter.convert(scheduled(distance: 5000), template: template(cues: ["Cue"]))
        let data = try JSONEncoder().encode(result)
        let back = try JSONDecoder().decode(WorkoutKitConversionResult.self, from: data)
        #expect(back == result)
    }

    @Test("Warnings are de-duplicated so the same disclosure is not repeated")
    func warningsAreDeduplicated() {
        let result = converter.convert(
            scheduled(sport: .swim),
            template: template(sport: .swim,
                               mainSet: [step(kind: .drill, seconds: nil, metres: 100),
                                         step(kind: .drill, seconds: nil, metres: 100)]))
        let drills = result.warnings.filter { $0 == .drillRepresentedAsWork }
        #expect(drills.count <= 1)
    }
}
