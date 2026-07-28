import Foundation

// MARK: - Framework-independent WorkoutKit representation

/// The observable fidelity of a WorkoutKit conversion. It deliberately says
/// nothing about authorization or whether the framework call succeeded.
public enum WorkoutKitConversionOutcome: String, Codable, Sendable, Hashable, CaseIterable {
    case exact
    case simplified
    case unsupported

    public var localizationKey: String { "workoutkit.conversion.\(rawValue)" }
    public var requiresConfirmation: Bool { self == .simplified }
    public var isSchedulable: Bool { self != .unsupported }
}

public enum WorkoutKitGoalRepresentation: Codable, Sendable, Hashable {
    case open
    case time(seconds: Int)
    case distance(metres: Double)
    case poolDistanceWithTime(metres: Double, seconds: Int)
}

public enum WorkoutKitAlertRepresentation: Codable, Sendable, Hashable {
    case heartRate(bpm: ClosedRange<Double>)
    case speed(metresPerSecond: ClosedRange<Double>)
    case power(watts: ClosedRange<Double>)
    case cadence(rpm: ClosedRange<Double>)
}

public struct WorkoutKitStepRepresentation: Codable, Sendable, Hashable, Identifiable {
    public enum Purpose: String, Codable, Sendable, Hashable { case work, recovery }

    public var id: UUID
    public var purpose: Purpose?
    public var goal: WorkoutKitGoalRepresentation
    public var alert: WorkoutKitAlertRepresentation?
    /// Uses the real Endurance label and RPE guidance as text; it is never a
    /// fabricated numeric alert.
    public var displayName: String?
    /// RPE is presentation guidance, not a synthetic sensor alert. The adapter
    /// resolves its localized text when a current SDK supports step names.
    public var perceivedExertionRange: ClosedRange<Int>?

    public init(
        id: UUID = UUID(),
        purpose: Purpose? = nil,
        goal: WorkoutKitGoalRepresentation,
        alert: WorkoutKitAlertRepresentation? = nil,
        displayName: String? = nil,
        perceivedExertionRange: ClosedRange<Int>? = nil
    ) {
        self.id = id
        self.purpose = purpose
        self.goal = goal
        self.alert = alert
        self.displayName = displayName
        self.perceivedExertionRange = perceivedExertionRange
    }
}

public struct WorkoutKitIntervalBlock: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var steps: [WorkoutKitStepRepresentation]
    public var iterations: Int

    public init(id: UUID = UUID(), steps: [WorkoutKitStepRepresentation], iterations: Int = 1) {
        self.id = id
        self.steps = steps
        self.iterations = max(1, iterations)
    }
}

public enum WorkoutKitActivityRepresentation: String, Codable, Sendable, Hashable {
    case running
    case cycling
    case swimming
    /// Carries strength work. HIIT is a first-class Watch workout type that
    /// accepts a time goal and interval blocks, which is what a strength circuit
    /// actually is. Filing it here is a deliberate approximation — see
    /// `activity(for:)` — chosen over sending nothing at all.
    case highIntensityIntervalTraining
    /// Carries continuous mobility work. See `mobilityActivity(for:)`.
    case functionalStrengthTraining
}

public enum WorkoutKitLocationRepresentation: String, Codable, Sendable, Hashable {
    case unknown
    case indoor
    case outdoor
    case pool
    case openWater
}

public enum WorkoutKitWorkoutRepresentation: Codable, Sendable, Hashable {
    case singleGoal(
        activity: WorkoutKitActivityRepresentation,
        location: WorkoutKitLocationRepresentation,
        goal: WorkoutKitGoalRepresentation
    )
    case custom(
        activity: WorkoutKitActivityRepresentation,
        location: WorkoutKitLocationRepresentation,
        displayName: String,
        warmup: WorkoutKitStepRepresentation?,
        blocks: [WorkoutKitIntervalBlock],
        cooldown: WorkoutKitStepRepresentation?
    )
    /// WorkoutKit can represent activity ordering only. Endurance currently
    /// refuses structured bricks/races rather than presenting this as a full
    /// representation of their transitions or legs.
    case swimBikeRun(activities: [WorkoutKitMultisportActivity], displayName: String)
}

public enum WorkoutKitMultisportActivity: Codable, Sendable, Hashable {
    case swimming(location: WorkoutKitLocationRepresentation)
    case cycling(location: WorkoutKitLocationRepresentation)
    case running(location: WorkoutKitLocationRepresentation)
}

public enum WorkoutKitConversionWarning: String, Codable, Sendable, Hashable, CaseIterable {
    case supplementalInstructionsRemainInEndurance
    case techniqueCuesRemainInEndurance
    case fuelingInstructionsRemainInEndurance
    case transitionInstructionsOmitted
    case nestedRepetitionsFlattened
    case stepsCombined
    case drillRepresentedAsWork
    case shortenedWorkoutUsesSingleGoal
    case rpePreservedAsText
    /// A multisport container carries the leg *order* and locations only —
    /// `SwimBikeRunWorkout` has no per-leg goals — so distances and durations
    /// stay in Endurance. Structural: what gets trained on the Watch genuinely
    /// differs from the plan, and the athlete must agree to that.
    case multisportLegTargetsRemainInEndurance

    public var localizationKey: String { "workoutkit.warning.\(rawValue)" }

    /// Whether this warning means the *workout itself* differs from the plan.
    ///
    /// The distinction decides whether an athlete must consent. Technique cues,
    /// fueling notes, gear lists and RPE text are supplemental: the Workout app
    /// has nowhere to display them, but every interval, goal and target still
    /// transfers intact, so the session performed on the Watch *is* the planned
    /// session. Combining steps, flattening repeats, dropping transitions or
    /// collapsing a shortened session to one goal genuinely change what gets
    /// trained, and those require explicit approval.
    ///
    /// Without this split, essentially the whole bundled plan converts as
    /// "simplified" — 34 of the first 60 sessions carry technique cues — and
    /// nothing would ever schedule automatically, making the feature look broken
    /// while being technically correct.
    public var isStructural: Bool {
        switch self {
        case .supplementalInstructionsRemainInEndurance,
             .techniqueCuesRemainInEndurance,
             .fuelingInstructionsRemainInEndurance,
             .rpePreservedAsText:
            return false
        case .multisportLegTargetsRemainInEndurance,
             .transitionInstructionsOmitted,
             .nestedRepetitionsFlattened,
             .stepsCombined,
             .drillRepresentedAsWork,
             .shortenedWorkoutUsesSingleGoal:
            return true
        }
    }
}

public enum WorkoutKitUnsupportedReason: String, Codable, Sendable, Hashable, CaseIterable {
    case unsupportedSport
    case brickRequiresLinkedComponents
    case raceRequiresStructuredMultisport
    case nestedRepetitions
    case invalidWorkoutStructure
    case unsupportedGoal
    case unsupportedAlert
    case missingTemplate
    case noSchedulableGoal

    public var localizationKey: String { "workoutkit.unsupported.\(rawValue)" }
}

/// One explicit, never-nil answer from the pure converter.
public struct WorkoutKitConversionResult: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var scheduledWorkoutID: UUID
    public var templateID: UUID?
    public var sport: Sport
    public var conversionVersion: Int
    public var outcome: WorkoutKitConversionOutcome
    public var representation: WorkoutKitWorkoutRepresentation?
    public var warnings: [WorkoutKitConversionWarning]
    public var unsupportedReasons: [WorkoutKitUnsupportedReason]
    /// Stable catalog keys; framework-free code never manufactures English UI
    /// copy. The app resolves these with the String Catalog.
    public var explanationKeys: [String]
    public var requiresUserConfirmation: Bool
    public var automaticSchedulingAllowed: Bool

    public init(
        id: UUID = UUID(),
        scheduledWorkoutID: UUID,
        templateID: UUID?,
        sport: Sport,
        conversionVersion: Int = WorkoutKitConversionResult.currentVersion,
        outcome: WorkoutKitConversionOutcome,
        representation: WorkoutKitWorkoutRepresentation?,
        warnings: [WorkoutKitConversionWarning] = [],
        unsupportedReasons: [WorkoutKitUnsupportedReason] = []
    ) {
        self.id = id
        self.scheduledWorkoutID = scheduledWorkoutID
        self.templateID = templateID
        self.sport = sport
        self.conversionVersion = conversionVersion
        self.outcome = outcome
        self.representation = representation
        self.warnings = warnings
        self.unsupportedReasons = unsupportedReasons
        self.explanationKeys = (warnings.map(\.localizationKey) + unsupportedReasons.map(\.localizationKey))
        self.requiresUserConfirmation = outcome.requiresConfirmation
        self.automaticSchedulingAllowed = outcome == .exact
    }

    public static let currentVersion = 2

    /// Stable enough to gate a previously approved simplification. It includes
    /// every persisted conversion field, not the conversion's random record ID.
    public var fingerprint: String {
        let warningPart = warnings.map(\.rawValue).sorted().joined(separator: ",")
        let unsupportedPart = unsupportedReasons.map(\.rawValue).sorted().joined(separator: ",")
        return "\(scheduledWorkoutID.uuidString)|\(conversionVersion)|\(outcome.rawValue)|\(warningPart)|\(unsupportedPart)"
    }
}

/// Compatibility spelling retained for the previously declared service seam.
public typealias WorkoutConversion = WorkoutKitConversionResult

public struct WorkoutStructure: Sendable, Hashable {
    public var warmup: [WorkoutStep]
    public var mainSet: [WorkoutStep]
    public var cooldown: [WorkoutStep]

    public init(warmup: [WorkoutStep], mainSet: [WorkoutStep], cooldown: [WorkoutStep]) {
        self.warmup = warmup
        self.mainSet = mainSet
        self.cooldown = cooldown
    }

    public init(template: WorkoutTemplate) {
        self.init(warmup: template.warmup, mainSet: template.mainSet, cooldown: template.cooldown)
    }
}

// MARK: - Pure conversion policy

/// Conservative conversion policy. It knows Endurance data only; the adapter
/// still asks WorkoutKit whether the resulting activity/goal/alert is supported
/// on the current device before scheduling.
public struct WorkoutKitConverter: Sendable {
    public init() {}

    public func convert(_ workout: ScheduledWorkout, template: WorkoutTemplate?) -> WorkoutKitConversionResult {
        guard let template else {
            return unsupported(workout, templateID: nil, reason: .missingTemplate)
        }
        if workout.isBrick || template.isBrick {
            return unsupported(workout, templateID: template.id, reason: .brickRequiresLinkedComponents)
        }
        if workout.sport == .race || template.sport == .race {
            return unsupported(workout, templateID: template.id, reason: .raceRequiresStructuredMultisport)
        }
        guard let activity = activity(for: workout.sport, template: template) else {
            return unsupported(workout, templateID: template.id, reason: .unsupportedSport)
        }

        var warnings = supplementalWarnings(for: template)
        let location = location(for: template.workoutLocation)

        // A user-shortened detailed session must not leave old intervals on the
        // Watch. A truthful single time goal is safer and explicitly disclosed.
        if workout.reducedDurationMinutes != nil {
            warnings.append(.shortenedWorkoutUsesSingleGoal)
            return result(
                workout, template: template, outcome: .simplified,
                representation: .singleGoal(activity: activity, location: location,
                                            goal: .time(seconds: workout.effectivePlannedMinutes * 60)),
                warnings: warnings)
        }

        let structure = WorkoutStructure(template: template)
        if structure.warmup.isEmpty && structure.mainSet.isEmpty && structure.cooldown.isEmpty {
            return result(
                workout, template: template,
                outcome: Self.outcome(for: warnings),
                representation: .singleGoal(activity: activity, location: location,
                                            goal: baseGoal(for: workout)),
                warnings: warnings)
        }

        if containsUnsupportedNesting(in: structure) {
            return unsupported(workout, templateID: template.id, reason: .nestedRepetitions,
                               warnings: warnings)
        }

        let warmup = structure.warmup.isEmpty ? nil : combinePhase(
            structure.warmup, activity: activity, location: location,
            warnings: &warnings)
        let cooldown = structure.cooldown.isEmpty ? nil : combinePhase(
            structure.cooldown, activity: activity, location: location,
            warnings: &warnings)
        guard (structure.warmup.isEmpty || warmup != nil),
              (structure.cooldown.isEmpty || cooldown != nil),
              let blocks = blocks(for: structure.mainSet, activity: activity, location: location,
                                  warnings: &warnings) else {
            return unsupported(workout, templateID: template.id, reason: .invalidWorkoutStructure,
                               warnings: warnings)
        }

        let hasRPE = allSteps(in: structure).contains { $0.intensity != nil && $0.target == nil }
        if hasRPE { warnings.append(.rpePreservedAsText) }
        return result(
            workout, template: template,
            outcome: Self.outcome(for: warnings),
            representation: .custom(activity: activity, location: location, displayName: workout.title,
                                    warmup: warmup, blocks: blocks, cooldown: cooldown),
            warnings: warnings)
    }

    // MARK: - Multisport (§I)

    /// Convert a brick or a race into a `SwimBikeRun` container.
    ///
    /// These were previously refused outright, which cost 71 of 382 sessions —
    /// and they are the most triathlon-specific work in the plan, the sessions
    /// an athlete would least want to improvise. WorkoutKit has a purpose-built
    /// multisport type; the refusal predated using it.
    ///
    /// Always `.simplified`, never `.exact`. `SwimBikeRunWorkout` carries the
    /// leg *order* and locations and nothing else — no distances, no durations,
    /// no intervals. The Watch will sequence the legs and handle transitions;
    /// the targets stay in Endurance. That is a real difference from the plan,
    /// so it is disclosed and requires approval rather than being sent silently.
    ///
    /// - Parameter components: the sessions forming the brick, in the order they
    ///   are performed. A race is a single session whose main set already
    ///   contains the legs, and is handled by `multisportLegs(fromRace:)`.
    public func convertMultisport(
        components: [(workout: ScheduledWorkout, template: WorkoutTemplate?)],
        displayName: String
    ) -> WorkoutKitConversionResult? {
        guard let anchor = components.first?.workout else { return nil }

        let legs: [WorkoutKitMultisportActivity] = components.compactMap { component in
            multisportActivity(sport: component.workout.sport,
                               location: component.template?.workoutLocation)
        }
        guard legs.count == components.count, legs.count >= 2 else {
            // A leg we cannot express means the container would misrepresent the
            // session. Refusing is better than sending a partial brick.
            return unsupported(anchor, templateID: components.first?.template?.id,
                               reason: .brickRequiresLinkedComponents)
        }

        return WorkoutKitConversionResult(
            scheduledWorkoutID: anchor.id,
            templateID: components.first?.template?.id,
            sport: anchor.sport,
            outcome: .simplified,
            representation: .swimBikeRun(activities: legs, displayName: displayName),
            warnings: [.multisportLegTargetsRemainInEndurance],
            unsupportedReasons: [])
    }

    /// The legs of a race, read from its own main set.
    ///
    /// A race is one session containing swim / T1 / bike / T2 / run, so the legs
    /// come from the steps rather than from sibling sessions. Transitions are
    /// dropped deliberately: `SwimBikeRunWorkout` inserts its own between legs,
    /// and passing ours through would double them.
    public func multisportLegs(fromRace template: WorkoutTemplate) -> [WorkoutKitMultisportActivity] {
        template.mainSet.compactMap { step in
            guard step.kind != .transition else { return nil }
            return sportFromLabel(step.label).flatMap {
                multisportActivity(sport: $0, location: template.workoutLocation)
            }
        }
    }

    public func convertRace(
        _ workout: ScheduledWorkout, template: WorkoutTemplate?
    ) -> WorkoutKitConversionResult {
        guard let template else {
            return unsupported(workout, templateID: nil, reason: .missingTemplate)
        }
        let legs = multisportLegs(fromRace: template)
        guard legs.count >= 2 else {
            return unsupported(workout, templateID: template.id,
                               reason: .raceRequiresStructuredMultisport)
        }
        return WorkoutKitConversionResult(
            scheduledWorkoutID: workout.id,
            templateID: template.id,
            sport: workout.sport,
            outcome: .simplified,
            representation: .swimBikeRun(activities: legs, displayName: workout.title),
            warnings: [.multisportLegTargetsRemainInEndurance],
            unsupportedReasons: [])
    }

    private func multisportActivity(
        sport: Sport, location: WorkoutLocation?
    ) -> WorkoutKitMultisportActivity? {
        let resolved = self.location(for: location)
        switch sport {
        case .swim: return .swimming(location: resolved)
        case .bike: return .cycling(location: resolved)
        case .run:  return .running(location: resolved)
        default:    return nil
        }
    }

    /// A race leg names its own discipline. Matching on the label is narrow and
    /// explicit rather than clever — an unrecognised leg yields nil and the race
    /// is refused, which is the safe direction.
    private func sportFromLabel(_ label: String) -> Sport? {
        let lowered = label.lowercased()
        if lowered.contains("swim") { return .swim }
        if lowered.contains("bike") || lowered.contains("cycle") || lowered.contains("ride") { return .bike }
        if lowered.contains("run") { return .run }
        return nil
    }

    /// `.simplified` only when something structural changed; supplemental
    /// disclosures are still reported, but do not gate scheduling.
    static func outcome(for warnings: [WorkoutKitConversionWarning]) -> WorkoutKitConversionOutcome {
        warnings.contains(where: \.isStructural) ? .simplified : .exact
    }

    private func unsupported(
        _ workout: ScheduledWorkout,
        templateID: UUID?,
        reason: WorkoutKitUnsupportedReason,
        warnings: [WorkoutKitConversionWarning] = []
    ) -> WorkoutKitConversionResult {
        WorkoutKitConversionResult(
            scheduledWorkoutID: workout.id, templateID: templateID, sport: workout.sport,
            outcome: .unsupported, representation: nil, warnings: warnings,
            unsupportedReasons: [reason])
    }

    private func result(
        _ workout: ScheduledWorkout,
        template: WorkoutTemplate,
        outcome: WorkoutKitConversionOutcome,
        representation: WorkoutKitWorkoutRepresentation,
        warnings: [WorkoutKitConversionWarning]
    ) -> WorkoutKitConversionResult {
        WorkoutKitConversionResult(
            scheduledWorkoutID: workout.id, templateID: template.id, sport: workout.sport,
            outcome: outcome, representation: representation, warnings: Array(Set(warnings)),
            unsupportedReasons: [])
    }

    /// Strength is filed as high-intensity interval training.
    ///
    /// This is an approximation, and a deliberate one. There is no strength
    /// activity WorkoutKit will schedule that also carries interval structure,
    /// and the previous policy — "no honest equivalent, send nothing" — meant a
    /// strength session simply never reached the Watch. HIIT accepts a time goal
    /// and interval blocks, which is structurally what a strength circuit is, and
    /// the Watch renders it as a real workout the athlete can start and complete.
    ///
    /// The cost is that the resulting HealthKit workout is recorded as HIIT
    /// rather than strength training. `HealthActivityMapping` therefore maps HIIT
    /// back to `.strength` on import, so a session completed on the Watch returns
    /// and matches its planned session rather than being dropped as unmapped.
    ///
    /// Mobility and recovery remain unsupported: yoga and flexibility carry no
    /// interval structure worth sending, and nothing is lost by leaving them off
    /// the Watch.
    private func activity(
        for sport: Sport, template: WorkoutTemplate?
    ) -> WorkoutKitActivityRepresentation? {
        switch sport {
        case .run: return .running
        case .bike: return .cycling
        case .swim: return .swimming
        case .strength: return .highIntensityIntervalTraining
        case .mobility: return Self.mobilityActivity(for: template)
        // Recovery is walking or nothing; a brick and a race are multisport and
        // are built by `convertMultisport` rather than as a single activity.
        case .recovery, .brick, .race: return nil
        }
    }

    /// Mobility maps to whichever of the two supported shapes the session
    /// actually resembles.
    ///
    /// A circuit — repeated work with recovery between — behaves like interval
    /// training. A continuous flow does not, and calling a thirty-minute
    /// mobility session "high intensity interval training" would misdescribe it
    /// on the athlete's wrist and in their Health data. Functional strength
    /// training is the closer of the two for continuous work.
    ///
    /// Every mobility session in the bundled plan is a single continuous flow,
    /// so all of them take the second branch today. The first exists for
    /// coach-authored plans (§28.12) built as circuits.
    static func mobilityActivity(for template: WorkoutTemplate?) -> WorkoutKitActivityRepresentation {
        guard let template else { return .functionalStrengthTraining }
        let steps = template.warmup + template.mainSet + template.cooldown
        let hasIntervalShape = steps.contains { $0.repeats > 1 || !$0.childSteps.isEmpty }
            || steps.filter { $0.kind == .work }.count > 1
        return hasIntervalShape ? .highIntensityIntervalTraining : .functionalStrengthTraining
    }

    private func location(for location: WorkoutLocation?) -> WorkoutKitLocationRepresentation {
        switch location {
        case .indoor: .indoor
        case .outdoor: .outdoor
        case .pool: .pool
        case .openWater: .openWater
        case nil: .unknown
        }
    }

    private func baseGoal(for workout: ScheduledWorkout) -> WorkoutKitGoalRepresentation {
        if let distance = workout.plannedDistanceMeters, distance > 0 { return .distance(metres: distance) }
        if workout.effectivePlannedMinutes > 0 { return .time(seconds: workout.effectivePlannedMinutes * 60) }
        return .open
    }

    private func supplementalWarnings(for template: WorkoutTemplate) -> [WorkoutKitConversionWarning] {
        var warnings: [WorkoutKitConversionWarning] = []
        if !template.techniqueCues.isEmpty { warnings.append(.techniqueCuesRemainInEndurance) }
        if template.fueling != nil || template.hydration != nil { warnings.append(.fuelingInstructionsRemainInEndurance) }
        if !template.gear.isEmpty || !template.safetyNotes.isEmpty { warnings.append(.supplementalInstructionsRemainInEndurance) }
        return warnings
    }

    private func containsUnsupportedNesting(in structure: WorkoutStructure) -> Bool {
        allSteps(in: structure).contains { step in
            step.childSteps.contains { !$0.childSteps.isEmpty }
        }
    }

    private func allSteps(in structure: WorkoutStructure) -> [WorkoutStep] {
        structure.warmup + structure.mainSet + structure.cooldown
    }

    /// `nil` means an empty phase; `some(nil)` is impossible in Swift, so an
    /// invalid phase is represented by returning nil only when it contains
    /// unrepresentable goals. Multiple compatible steps are combined, visibly
    /// marked as a simplification.
    private func combinePhase(
        _ steps: [WorkoutStep],
        activity: WorkoutKitActivityRepresentation,
        location: WorkoutKitLocationRepresentation,
        warnings: inout [WorkoutKitConversionWarning]
    ) -> WorkoutKitStepRepresentation? {
        guard !steps.isEmpty else { return nil }
        if steps.count == 1, let step = steps.first, step.childSteps.isEmpty {
            return stepRepresentation(step, purpose: nil, activity: activity, location: location, warnings: &warnings)
        }
        let direct = steps.filter { $0.childSteps.isEmpty }
        guard direct.count == steps.count,
              direct.allSatisfy({ $0.target == nil && !$0.isOpenGoal }) else { return nil }
        let durations = direct.compactMap(\.durationSeconds)
        let distances = direct.compactMap(\.distanceMeters)
        if durations.count == direct.count {
            warnings.append(.stepsCombined)
            return WorkoutKitStepRepresentation(goal: .time(seconds: durations.reduce(0, +)), displayName: direct.first?.label)
        }
        if distances.count == direct.count {
            warnings.append(.stepsCombined)
            return WorkoutKitStepRepresentation(goal: .distance(metres: distances.reduce(0, +)), displayName: direct.first?.label)
        }
        return nil
    }

    private func blocks(
        for steps: [WorkoutStep],
        activity: WorkoutKitActivityRepresentation,
        location: WorkoutKitLocationRepresentation,
        warnings: inout [WorkoutKitConversionWarning]
    ) -> [WorkoutKitIntervalBlock]? {
        guard !steps.isEmpty else { return [] }
        var blocks: [WorkoutKitIntervalBlock] = []
        var flat: [WorkoutKitStepRepresentation] = []

        func flushFlat() {
            guard !flat.isEmpty else { return }
            blocks.append(WorkoutKitIntervalBlock(steps: flat))
            flat.removeAll()
        }

        for step in steps {
            if step.childSteps.isEmpty {
                guard let converted = stepRepresentation(step, purpose: purpose(for: step.kind),
                                                         activity: activity, location: location,
                                                         warnings: &warnings) else { return nil }
                flat.append(converted)
                continue
            }
            flushFlat()
            guard step.childSteps.allSatisfy({ $0.childSteps.isEmpty }) else { return nil }
            var converted: [WorkoutKitStepRepresentation] = []
            for child in step.childSteps {
                guard let childStep = stepRepresentation(
                    child, purpose: purpose(for: child.kind), activity: activity,
                    location: location, warnings: &warnings
                ) else { return nil }
                converted.append(childStep)
            }
            blocks.append(WorkoutKitIntervalBlock(steps: converted, iterations: step.repeats))
        }
        flushFlat()
        return blocks
    }

    private func purpose(for kind: StepKind) -> WorkoutKitStepRepresentation.Purpose? {
        switch kind {
        case .recovery, .rest: .recovery
        case .work, .steady, .drill: .work
        case .warmup, .cooldown, .transition: nil
        }
    }

    private func stepRepresentation(
        _ step: WorkoutStep,
        purpose: WorkoutKitStepRepresentation.Purpose?,
        activity: WorkoutKitActivityRepresentation,
        location: WorkoutKitLocationRepresentation,
        warnings: inout [WorkoutKitConversionWarning]
    ) -> WorkoutKitStepRepresentation? {
        if step.kind == .transition {
            warnings.append(.transitionInstructionsOmitted)
            return nil
        }
        if step.kind == .drill { warnings.append(.drillRepresentedAsWork) }
        let goal: WorkoutKitGoalRepresentation
        if let distance = step.distanceMeters, distance > 0,
           let seconds = step.durationSeconds, seconds > 0,
           activity == .swimming, location == .pool {
            goal = .poolDistanceWithTime(metres: distance, seconds: seconds)
        } else if let distance = step.distanceMeters, distance > 0 {
            goal = .distance(metres: distance)
        } else if let seconds = step.durationSeconds, seconds > 0 {
            goal = .time(seconds: seconds)
        } else if step.isOpenGoal {
            goal = .open
        } else {
            return nil
        }
        let alert: WorkoutKitAlertRepresentation?
        switch step.target {
        case .heartRate(let bpm): alert = .heartRate(bpm: bpm)
        case .speed(let speed): alert = .speed(metresPerSecond: speed)
        case .power(let watts): alert = .power(watts: watts)
        case .cadence(let rpm): alert = .cadence(rpm: rpm)
        case nil: alert = nil
        }
        let rpe = step.intensity?.rpeRange
        return WorkoutKitStepRepresentation(purpose: purpose, goal: goal, alert: alert,
                                             displayName: step.label.isEmpty ? nil : step.label,
                                             perceivedExertionRange: rpe)
    }
}

// MARK: - Scheduling representation

public enum WorkoutKitSchedulingHorizon: String, Codable, Sendable, Hashable, CaseIterable {
    case off
    case nextWorkout
    case days3
    case days7
    case days14

    public var days: Int? {
        switch self {
        case .off: nil
        case .nextWorkout: 0
        case .days3: 3
        case .days7: 7
        case .days14: 14
        }
    }
    public var localizationKey: String { "workoutkit.horizon.\(rawValue)" }
}

public struct WorkoutKitSchedulingPreferences: Codable, Sendable, Hashable {
    public var isEnabled: Bool
    public var horizon: WorkoutKitSchedulingHorizon
    public var lastSuccessfulSynchronization: Date?

    public init(
        isEnabled: Bool = false,
        horizon: WorkoutKitSchedulingHorizon = .nextWorkout,
        lastSuccessfulSynchronization: Date? = nil
    ) {
        self.isEnabled = isEnabled
        self.horizon = horizon
        self.lastSuccessfulSynchronization = lastSuccessfulSynchronization
    }
}

public extension WorkoutKitConversionResult {
    /// A stable WorkoutKit identity, scoped to conversion behaviour so a future
    /// meaningful output change cannot accidentally manage an obsolete plan.
    var deterministicWorkoutPlanID: UUID {
        UUID.endurance(schedule: "workoutkit|\(scheduledWorkoutID.uuidString)|v\(conversionVersion)")
    }
}

public enum WorkoutKitScheduleStatus: String, Codable, Sendable, Hashable, CaseIterable {
    case notEvaluated
    case exactAvailable
    case simplifiedAvailable
    case unsupported
    case authorizationRequired
    case scheduling
    case scheduled
    case rescheduling
    case removing
    case removed
    case failedRetryable
    case failedPermanent
    case stale

    public var localizationKey: String { "workoutkit.status.\(rawValue)" }
}

public enum WorkoutKitFailureCategory: String, Codable, Sendable, Hashable {
    case workoutKitUnavailable
    case authorizationRequired
    case authorizationDenied
    case conversionUnsupported
    case simplificationNotApproved
    case invalidWorkoutStructure
    case unsupportedGoal
    case unsupportedAlert
    case unsupportedMultisport
    case scheduleFailed
    case rescheduleFailed
    case removalFailed
    case duplicatePrevented
    case staleSchedule
    case persistenceFailedAfterSchedule
    case reconciliationRequired

    public enum Classification: String, Codable, Sendable, Hashable {
        case retryable
        case userActionRequired
        case permanentForWorkout
        case unavailableOnDevice
        case internalConsistencyFailure
    }

    public var classification: Classification {
        switch self {
        case .scheduleFailed, .rescheduleFailed, .removalFailed, .staleSchedule: .retryable
        case .authorizationRequired, .authorizationDenied, .simplificationNotApproved: .userActionRequired
        case .conversionUnsupported, .invalidWorkoutStructure, .unsupportedGoal, .unsupportedAlert, .unsupportedMultisport: .permanentForWorkout
        case .workoutKitUnavailable: .unavailableOnDevice
        case .duplicatePrevented, .persistenceFailedAfterSchedule, .reconciliationRequired: .internalConsistencyFailure
        }
    }
}

public enum WorkoutKitSchedulingError: Error, Sendable, Equatable {
    case workoutKitUnavailable
    case authorizationRequired
    case authorizationDenied
    case conversionUnsupported
    case simplificationNotApproved
    case invalidWorkoutStructure
    case unsupportedGoal
    case unsupportedAlert
    case unsupportedMultisport
    case scheduleFailed
    case rescheduleFailed
    case removalFailed
    case duplicatePrevented
    case staleSchedule
    case persistenceFailedAfterSchedule
    case reconciliationRequired

    public var category: WorkoutKitFailureCategory {
        switch self {
        case .workoutKitUnavailable: .workoutKitUnavailable
        case .authorizationRequired: .authorizationRequired
        case .authorizationDenied: .authorizationDenied
        case .conversionUnsupported: .conversionUnsupported
        case .simplificationNotApproved: .simplificationNotApproved
        case .invalidWorkoutStructure: .invalidWorkoutStructure
        case .unsupportedGoal: .unsupportedGoal
        case .unsupportedAlert: .unsupportedAlert
        case .unsupportedMultisport: .unsupportedMultisport
        case .scheduleFailed: .scheduleFailed
        case .rescheduleFailed: .rescheduleFailed
        case .removalFailed: .removalFailed
        case .duplicatePrevented: .duplicatePrevented
        case .staleSchedule: .staleSchedule
        case .persistenceFailedAfterSchedule: .persistenceFailedAfterSchedule
        case .reconciliationRequired: .reconciliationRequired
        }
    }
}
