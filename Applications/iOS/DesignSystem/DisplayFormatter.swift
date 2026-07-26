import Foundation
import EnduranceDomain

/// View-facing formatting that binds the domain `UnitFormatter` to the athlete's
/// chosen units. Keeps all number/units formatting in one place.
struct DisplayFormatter {
    let units: MeasurementSystem
    private let f = UnitFormatter()

    func distance(_ meters: Double?, sport: Sport) -> String? {
        guard let meters, meters > 0 else { return nil }
        return f.distanceString(meters: meters, sport: sport, system: units)
    }

    func duration(minutes: Int) -> String { f.durationString(minutes: minutes) }

    func intensity(_ zone: IntensityZone) -> String {
        if let z = zone.zoneShorthand { return "\(z) · \(zone.englishName)" }
        return zone.englishName
    }

    /// A concise "RPE 3–4" hint for the sensor-free case.
    func rpeHint(_ zone: IntensityZone) -> String {
        let r = zone.rpeRange
        return "RPE \(r.lowerBound)–\(r.upperBound)"
    }

    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    static func longDate(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }
}
