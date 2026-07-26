import Foundation

/// The kind of a single step inside a structured workout. Used to render the
/// warm-up / main-set / cool-down layout (§9) rather than a wall of text.
public enum StepKind: String, Codable, CaseIterable, Sendable, Hashable {
    case warmup
    case work        // a hard/quality repetition
    case recovery    // easy interval between reps
    case steady      // sustained aerobic block
    case cooldown
    case drill       // technique drill (esp. swim)
    case transition  // brick transition
    case rest        // complete rest between sets

    public var localizationKey: String { "step.\(rawValue)" }
}

/// An explicitly authored numeric target. The plan currently uses RPE by
/// default, so this is intentionally optional: a numeric alert exists only
/// when a plan or a future athlete setting has supplied real values.
public enum WorkoutTarget: Codable, Sendable, Hashable {
    case heartRate(bpm: ClosedRange<Double>)
    /// Metres per second. Pace is converted to this only when an explicit pace
    /// range is supplied by authored plan data or a future zone setting.
    case speed(metresPerSecond: ClosedRange<Double>)
    case power(watts: ClosedRange<Double>)
    case cadence(rpm: ClosedRange<Double>)
}

/// One node of a structured workout. Recursive: a node with `repeats > 1` and
/// non-empty `childSteps` represents a repeated block, e.g.
/// `4 × (6 min Zone 3 + 3 min easy)`.
///
/// Goals are optional and mutually informative: a step may be time-based
/// (`durationSeconds`), distance-based (`distanceMeters`), both, or open
/// (`isOpenGoal`, e.g. "swim until loose"). Storing seconds/meters keeps the
/// content unit-agnostic; `UnitFormatter` renders it in the athlete's units.
public struct WorkoutStep: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var kind: StepKind
    /// Short human label, e.g. "Easy", "Zone 3", "Catch-up drill".
    public var label: String
    public var durationSeconds: Int?
    public var distanceMeters: Double?
    public var isOpenGoal: Bool
    public var intensity: IntensityZone?
    /// Never inferred from an RPE/Zone label. Nil means the step has no numeric
    /// sensor target that WorkoutKit may turn into an alert.
    public var target: WorkoutTarget?
    /// Number of times to perform this node (and its `childSteps`). 1 = once.
    public var repeats: Int
    /// The repeated sub-sequence when this node is a repeat block.
    public var childSteps: [WorkoutStep]
    public var note: String?

    public init(
        id: UUID = UUID(),
        kind: StepKind,
        label: String,
        durationSeconds: Int? = nil,
        distanceMeters: Double? = nil,
        isOpenGoal: Bool = false,
        intensity: IntensityZone? = nil,
        target: WorkoutTarget? = nil,
        repeats: Int = 1,
        childSteps: [WorkoutStep] = [],
        note: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.label = label
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
        self.isOpenGoal = isOpenGoal
        self.intensity = intensity
        self.target = target
        self.repeats = repeats
        self.childSteps = childSteps
        self.note = note
    }

    /// Total time this node contributes, expanding repeats and children.
    /// Returns 0 for purely distance/open steps (their time is not fixed).
    public var expandedDurationSeconds: Int {
        let ownDuration = durationSeconds ?? 0
        let childDuration = childSteps.reduce(0) { $0 + $1.expandedDurationSeconds }
        return (ownDuration + childDuration) * max(1, repeats)
    }
}
