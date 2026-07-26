import Foundation

/// Planned intensity of a session, expressed as a training zone. Zones are the
/// portable, sensor-independent way to prescribe effort: the app remains useful
/// with nothing but perceived exertion, and richer targets (HR/power/pace) are
/// layered on in Settings → Training Zones when the athlete has them.
///
/// A five-zone model is used because it is the most widely taught scheme across
/// reputable endurance-coaching sources and maps cleanly onto RPE.
public enum IntensityZone: String, Codable, CaseIterable, Sendable, Hashable {
    case recovery     // Z1 — very easy, active recovery
    case endurance    // Z2 — aerobic base, "all day" pace
    case tempo        // Z3 — steady, "comfortably hard"
    case threshold    // Z4 — lactate/functional threshold
    case vo2          // Z5 — hard intervals
    case variable     // mixed within one session (e.g. fartlek, race sim)
    case raceEffort   // deliberate race-pace practice

    public var localizationKey: String { "intensity.\(rawValue)" }

    public var englishName: String {
        switch self {
        case .recovery: return "Recovery"
        case .endurance: return "Endurance"
        case .tempo: return "Tempo"
        case .threshold: return "Threshold"
        case .vo2: return "VO₂"
        case .variable: return "Variable"
        case .raceEffort: return "Race effort"
        }
    }

    /// Perceived-exertion range on the 1–10 (Borg CR10-style) scale. This is the
    /// universal fallback shown when no HR/power/pace zones are configured.
    public var rpeRange: ClosedRange<Int> {
        switch self {
        case .recovery: return 1...2
        case .endurance: return 3...4
        case .tempo: return 5...6
        case .threshold: return 7...8
        case .vo2: return 9...10
        case .variable: return 3...8
        case .raceEffort: return 6...8
        }
    }

    /// Short zone label, e.g. "Z2". `nil` for non-single-zone intensities.
    public var zoneShorthand: String? {
        switch self {
        case .recovery: return "Z1"
        case .endurance: return "Z2"
        case .tempo: return "Z3"
        case .threshold: return "Z4"
        case .vo2: return "Z5"
        case .variable, .raceEffort: return nil
        }
    }
}
