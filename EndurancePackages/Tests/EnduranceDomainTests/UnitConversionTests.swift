import Testing
import Foundation
@testable import EnduranceDomain

@Suite("Unit conversion & formatting")
struct UnitConversionTests {
    let f = UnitFormatter()

    @Test("Meters convert exactly to miles, km, and yards")
    func conversions() {
        #expect(abs(f.convertedValue(meters: 1609.344, to: .miles) - 1.0) < 1e-9)
        #expect(abs(f.convertedValue(meters: 5000, to: .kilometers) - 5.0) < 1e-9)
        #expect(abs(f.convertedValue(meters: 91.44, to: .yards) - 100.0) < 1e-9)
        #expect(f.convertedValue(meters: 42, to: .meters) == 42)
    }

    @Test("Round-tripping through a unit preserves the value")
    func roundTrip() {
        for meters in [100.0, 1609.344, 42195.0, 3862.0] {
            for unit in [UnitLength.miles, .kilometers, .yards, .meters] {
                let v = f.convertedValue(meters: meters, to: unit)
                let back = f.meters(from: v, in: unit)
                #expect(abs(back - meters) < 1e-6)
            }
        }
    }

    @Test("Display unit depends on sport and system")
    func displayUnit() {
        #expect(f.displayUnit(for: .swim, system: .metric) == .meters)
        #expect(f.displayUnit(for: .swim, system: .imperial) == .yards)
        #expect(f.displayUnit(for: .swim, system: .mixedTriathlon) == .meters)
        #expect(f.displayUnit(for: .bike, system: .metric) == .kilometers)
        #expect(f.displayUnit(for: .run, system: .imperial) == .miles)
        #expect(f.displayUnit(for: .bike, system: .mixedTriathlon) == .miles)
    }

    @Test("Duration formatting")
    func duration() {
        #expect(f.durationString(minutes: 90) == "1h 30m")
        #expect(f.durationString(minutes: 60) == "1h")
        #expect(f.durationString(minutes: 45) == "45m")
        #expect(f.clockString(seconds: 3630) == "1:00:30")
        #expect(f.clockString(seconds: 360) == "6:00")
    }

    @Test("Distance string uses a POSIX locale deterministically")
    func distanceString() {
        let s = f.distanceString(meters: 1609.344, sport: .run, system: .imperial, locale: Locale(identifier: "en_US_POSIX"))
        #expect(s == "1 mi")
        let swim = f.distanceString(meters: 2500, sport: .swim, system: .metric, locale: Locale(identifier: "en_US_POSIX"))
        #expect(swim == "2,500 m" || swim == "2500 m")
    }
}
