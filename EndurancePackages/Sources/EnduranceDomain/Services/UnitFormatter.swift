import Foundation

/// Converts and formats normalized internal units (meters, minutes/seconds) for
/// display. The domain stores meters + seconds everywhere; this is the single
/// presentation boundary (§12 "Store normalized internal units and format for
/// display").
public struct UnitFormatter: Sendable {
    public init() {}

    // Exact conversion constants.
    static let metersPerKilometer = 1000.0
    static let metersPerMile = 1609.344
    static let metersPerYard = 0.9144

    /// The unit a distance should be shown in, given the discipline and system.
    /// Pool swims use the pool unit (m/yd); everything else uses the road unit.
    public func displayUnit(for sport: Sport, system: MeasurementSystem) -> UnitLength {
        switch sport {
        case .swim: return system.poolUnit
        default: return system.roadUnit
        }
    }

    /// Numeric conversion of meters into the display unit's value. Pure and
    /// deterministic — the unit-conversion tests assert against this directly.
    public func convertedValue(meters: Double, to unit: UnitLength) -> Double {
        switch unit {
        case .kilometers: return meters / Self.metersPerKilometer
        case .miles: return meters / Self.metersPerMile
        case .yards: return meters / Self.metersPerYard
        case .meters: return meters
        default:
            // Fall back through Measurement for any other unit.
            return Measurement(value: meters, unit: UnitLength.meters).converted(to: unit).value
        }
    }

    /// Inverse conversion, for parsing user-entered distances back to meters.
    public func meters(from value: Double, in unit: UnitLength) -> Double {
        switch unit {
        case .kilometers: return value * Self.metersPerKilometer
        case .miles: return value * Self.metersPerMile
        case .yards: return value * Self.metersPerYard
        case .meters: return value
        default:
            return Measurement(value: value, unit: unit).converted(to: .meters).value
        }
    }

    /// Formatted distance string, e.g. "3.86 mi", "2,500 m". Locale-aware.
    public func distanceString(
        meters: Double,
        sport: Sport,
        system: MeasurementSystem,
        locale: Locale = .current
    ) -> String {
        let unit = displayUnit(for: sport, system: system)
        let value = convertedValue(meters: meters, to: unit)
        let fractionDigits = (unit == .meters || unit == .yards) ? 0 : 2
        let nf = NumberFormatter()
        nf.locale = locale
        nf.numberStyle = .decimal
        nf.maximumFractionDigits = fractionDigits
        nf.minimumFractionDigits = 0
        let number = nf.string(from: NSNumber(value: value)) ?? "\(value)"
        return "\(number) \(unit.symbol)"
    }

    /// Formatted duration from whole minutes, e.g. "1h 30m", "45m".
    public func durationString(minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        if h > 0 && m > 0 { return "\(h)h \(m)m" }
        if h > 0 { return "\(h)h" }
        return "\(m)m"
    }

    /// Formatted duration from seconds, e.g. "6:00", "1:04:30".
    public func clockString(seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}
