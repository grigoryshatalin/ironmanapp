import Foundation

/// Physiological load category for a session. Drives the *safety* rules
/// (§14): the app uses these — not completion percentages — to decide whether a
/// proposed reschedule would stack high-stress days.
public enum StressCategory: String, Codable, CaseIterable, Sendable, Hashable {
    case recovery
    case easy
    case moderate
    case hard
    case long
    case raceSpecific

    public var localizationKey: String { "stress.\(rawValue)" }

    public var englishName: String {
        switch self {
        case .recovery: return "Recovery"
        case .easy: return "Easy"
        case .moderate: return "Moderate"
        case .hard: return "Hard"
        case .long: return "Long"
        case .raceSpecific: return "Race-specific"
        }
    }

    /// A rough relative-load weight, used only for ordering and for warning
    /// heuristics — never presented to the user as a precise physiological
    /// number. Deliberately coarse.
    public var relativeLoad: Int {
        switch self {
        case .recovery: return 0
        case .easy: return 1
        case .moderate: return 2
        case .hard: return 4
        case .long: return 4
        case .raceSpecific: return 5
        }
    }

    /// Sessions that impose meaningful systemic stress. Two of these on
    /// consecutive days triggers an advisory warning when rescheduling.
    public var isHighStress: Bool {
        switch self {
        case .recovery, .easy, .moderate: return false
        case .hard, .long, .raceSpecific: return true
        }
    }
}
