import Foundation

/// Fueling guidance for a session, framed as **configurable practice targets**,
/// never as personalized medical nutrition advice (§16). Ranges, not exact
/// prescriptions. All optional — many easy sessions need none.
public struct FuelingGuidance: Codable, Sendable, Hashable {
    /// Suggested carbohydrate intake range, grams per hour, for the session.
    public var carbsGramsPerHourLow: Int?
    public var carbsGramsPerHourHigh: Int?
    /// Free-text practice note, e.g. "Practice race-day gels every 25 min."
    public var note: String?
    /// True for long/key sessions where fueling is itself part of the training.
    public var isKeyFuelingSession: Bool

    public init(
        carbsGramsPerHourLow: Int? = nil,
        carbsGramsPerHourHigh: Int? = nil,
        note: String? = nil,
        isKeyFuelingSession: Bool = false
    ) {
        self.carbsGramsPerHourLow = carbsGramsPerHourLow
        self.carbsGramsPerHourHigh = carbsGramsPerHourHigh
        self.note = note
        self.isKeyFuelingSession = isKeyFuelingSession
    }
}

/// Hydration guidance, also as ranges/targets. Separate from fueling per §9.
public struct HydrationGuidance: Codable, Sendable, Hashable {
    public var fluidsMillilitresPerHourLow: Int?
    public var fluidsMillilitresPerHourHigh: Int?
    public var note: String?

    public init(
        fluidsMillilitresPerHourLow: Int? = nil,
        fluidsMillilitresPerHourHigh: Int? = nil,
        note: String? = nil
    ) {
        self.fluidsMillilitresPerHourLow = fluidsMillilitresPerHourLow
        self.fluidsMillilitresPerHourHigh = fluidsMillilitresPerHourHigh
        self.note = note
    }
}

/// Whole-day nutrition prompt (not per-session). Kept deliberately light and
/// non-prescriptive.
public struct DayNutrition: Codable, Sendable, Hashable {
    public var summary: String
    public var fueling: FuelingGuidance?
    public var hydration: HydrationGuidance?

    public init(summary: String, fueling: FuelingGuidance? = nil, hydration: HydrationGuidance? = nil) {
        self.summary = summary
        self.fueling = fueling
        self.hydration = hydration
    }
}

/// Recovery / mobility guidance attached to a day or week.
public struct RecoveryGuidance: Codable, Sendable, Hashable {
    public var summary: String
    /// Optional prompts, e.g. "10 min mobility", "Legs up the wall 5 min".
    public var prompts: [String]

    public init(summary: String, prompts: [String] = []) {
        self.summary = summary
        self.prompts = prompts
    }
}
