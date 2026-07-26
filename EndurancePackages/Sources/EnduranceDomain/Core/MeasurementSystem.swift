import Foundation

/// Display unit preference. The domain stores everything normalized —
/// **distance in meters, duration in seconds** — and only converts at the
/// presentation boundary via `UnitFormatter`. This keeps arithmetic exact and
/// DST/rounding bugs out of stored data.
public enum MeasurementSystem: String, Codable, CaseIterable, Sendable, Hashable {
    /// Kilometers and meters throughout.
    case metric
    /// Miles, with yards for the pool.
    case imperial
    /// The common triathlon convention: km/miles per the athlete's road unit,
    /// but pool swims in meters and open-water in the road unit. We model it as
    /// a road unit plus a pool unit.
    case mixedTriathlon

    public var localizationKey: String { "units.\(rawValue)" }

    public var englishName: String {
        switch self {
        case .metric: return "Metric (km · m)"
        case .imperial: return "Imperial (mi · yd)"
        case .mixedTriathlon: return "Triathlon (mi · m)"
        }
    }

    /// Unit used for road distances (bike/run).
    public var roadUnit: UnitLength {
        switch self {
        case .metric: return .kilometers
        case .imperial, .mixedTriathlon: return .miles
        }
    }

    /// Unit used for pool-swim distances.
    public var poolUnit: UnitLength {
        switch self {
        case .metric, .mixedTriathlon: return .meters
        case .imperial: return .yards
        }
    }
}
