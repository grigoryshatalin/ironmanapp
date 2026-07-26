import Foundation

/// A discipline or session category. Purely descriptive data — the domain layer
/// never imports SwiftUI, so we expose *token names* (SF Symbol strings, color
/// tokens) that the UI layer resolves into real symbols and semantic colors.
///
/// Color is always paired with a symbol and a label so status/type is never
/// conveyed by color alone (accessibility requirement, HIG "Differentiate
/// Without Color").
public enum Sport: String, Codable, CaseIterable, Sendable, Hashable {
    case swim
    case bike
    case run
    case strength
    case mobility
    case recovery
    case brick
    case race

    /// Localization key for the display name. The UI resolves this against the
    /// String Catalog; the domain never hard-codes user-facing English.
    public var localizationKey: String { "sport.\(rawValue)" }

    /// English fallback used only where no localization context exists
    /// (e.g. export files, logs, previews).
    public var englishName: String {
        switch self {
        case .swim: return "Swim"
        case .bike: return "Bike"
        case .run: return "Run"
        case .strength: return "Strength"
        case .mobility: return "Mobility"
        case .recovery: return "Recovery"
        case .brick: return "Brick"
        case .race: return "Race"
        }
    }

    /// Preferred SF Symbol name for the target SDK. Availability is verified in
    /// the UI layer against `fallbackSymbolName`.
    public var preferredSymbolName: String {
        switch self {
        case .swim: return "figure.pool.swim"
        case .bike: return "bicycle"
        case .run: return "figure.run"
        case .strength: return "dumbbell"
        case .mobility: return "figure.cooldown"
        case .recovery: return "bed.double"
        case .brick: return "figure.mixed.cardio"
        case .race: return "flag.checkered"
        }
    }

    /// A symbol guaranteed to exist far back in the SF Symbols catalog. The UI
    /// falls back to this when `preferredSymbolName` is unavailable on-device.
    public var fallbackSymbolName: String {
        switch self {
        case .swim: return "drop"
        case .bike: return "bicycle"
        case .run: return "figure.walk"
        case .strength: return "figure.strengthtraining.traditional"
        case .mobility: return "figure.flexibility"
        case .recovery: return "moon.zzz"
        case .brick: return "arrow.triangle.2.circlepath"
        case .race: return "flag"
        }
    }

    /// Semantic accent-color token (resolved to a `Color` in the design system).
    /// Restrained sport accents per the visual direction; secondary to content.
    public var accentToken: AccentToken {
        switch self {
        case .swim: return .swim
        case .bike: return .bike
        case .run: return .run
        case .strength: return .strength
        case .mobility, .recovery: return .recovery
        case .brick: return .bike // bricks are bike→run; anchor on bike accent
        case .race: return .race
        }
    }

    /// True for disciplines whose primary planned metric is distance (meters);
    /// false for time-first sessions. Drives which field the detail view leads
    /// with, but both are always available.
    public var isDistanceLed: Bool {
        switch self {
        case .swim: return true
        case .bike, .run: return false // long-course bike/run lead with duration
        case .strength, .mobility, .recovery, .brick, .race: return false
        }
    }
}

/// Semantic color token. The design system maps these to system colors so the
/// app follows Light/Dark/Increased-Contrast automatically. Kept in the domain
/// so plan content and snapshots can reference a stable token without SwiftUI.
public enum AccentToken: String, Codable, CaseIterable, Sendable, Hashable {
    case swim      // system cyan/blue
    case bike      // system orange
    case run       // system green
    case strength  // system indigo
    case recovery  // secondary / purple
    case race      // app primary accent
}
