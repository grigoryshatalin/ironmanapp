import Foundation
import EnduranceDomain

/// Generates realistic synthetic training history for testing the HealthKit
/// import path against a *real* health store.
///
/// Why this exists: HealthKit has no file-import mechanism. Samples only enter
/// through the API, so there is no dataset that can be downloaded to exercise
/// the read path. Something has to write them, and that something should produce
/// data shaped like a real athlete's — varied sports, plausible paces, the
/// occasional short or missed session — rather than three identical 60-minute
/// runs that pass every matcher rule by accident.
///
/// The plan generation is deliberately **pure and platform-independent**, so the
/// realism rules are unit-tested on the host. Only `HealthKitDataSeeder` (below)
/// touches HealthKit.
public struct SeededWorkout: Sendable, Hashable, Identifiable {
    public var id: UUID
    public var sport: Sport
    public var start: Date
    public var durationSeconds: Int
    public var distanceMeters: Double?
    public var activeEnergyKilocalories: Double?
    public var averageHeartRate: Double?
    public var isIndoor: Bool?
    public var isOpenWater: Bool?

    public init(
        id: UUID = UUID(),
        sport: Sport,
        start: Date,
        durationSeconds: Int,
        distanceMeters: Double? = nil,
        activeEnergyKilocalories: Double? = nil,
        averageHeartRate: Double? = nil,
        isIndoor: Bool? = nil,
        isOpenWater: Bool? = nil
    ) {
        self.id = id
        self.sport = sport
        self.start = start
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
        self.activeEnergyKilocalories = activeEnergyKilocalories
        self.averageHeartRate = averageHeartRate
        self.isIndoor = isIndoor
        self.isOpenWater = isOpenWater
    }

    public var end: Date { start.addingTimeInterval(TimeInterval(durationSeconds)) }
}

/// Builds a synthetic history. Deterministic given a seed, so a failing import
/// can be reproduced exactly.
public struct HealthSeedPlan: Sendable {

    /// How closely the seeded data should resemble the athlete's plan.
    public enum Shape: String, Sendable, CaseIterable {
        /// Sessions that line up closely with planned ones — exercises the
        /// happy path of the matcher.
        case matchingPlan
        /// Deliberately offset and mismatched — exercises `possible`, `none`
        /// and the Health Inbox review flow.
        case looselyRelated
        /// A mix, which is what a real store looks like.
        case realistic
    }

    public var shape: Shape
    public var dayCount: Int
    public var seed: UInt64

    public init(shape: Shape = .realistic, dayCount: Int = 14, seed: UInt64 = 42) {
        self.shape = shape
        self.dayCount = dayCount
        self.seed = seed
    }

    /// Build the synthetic sessions, optionally anchored to real planned
    /// sessions so matching can be exercised end to end.
    public func build(
        relativeTo now: Date,
        planned: [ScheduledWorkout] = [],
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> [SeededWorkout] {
        var rng = SeededGenerator(seed: seed)
        var results: [SeededWorkout] = []

        let windowStart = calendar.date(byAdding: .day, value: -dayCount, to: now) ?? now
        let recentPlanned = planned
            .filter { $0.plannedStart >= windowStart && $0.plannedStart <= now }
            .sorted { $0.plannedStart < $1.plannedStart }

        if shape != .looselyRelated, !recentPlanned.isEmpty {
            for workout in recentPlanned {
                // A real athlete misses sessions. Seeding a perfect record would
                // never exercise the unmatched-session paths.
                guard rng.next(upTo: 100) < 75 else { continue }
                guard let sport = importableSport(for: workout.sport) else { continue }

                // Start within a plausible window of the plan, not exactly on it.
                let offsetMinutes = Int(rng.next(upTo: 50)) - 20
                let start = workout.plannedStart.addingTimeInterval(TimeInterval(offsetMinutes * 60))

                // Duration within ±20% of planned.
                let planned = max(1, workout.effectivePlannedMinutes)
                let variance = Double(rng.next(upTo: 40)) / 100.0 - 0.20
                let minutes = max(6, Int(Double(planned) * (1 + variance)))

                results.append(session(
                    sport: sport, start: start, minutes: minutes,
                    plannedDistance: workout.plannedDistanceMeters, rng: &rng))
            }
        }

        if shape != .matchingPlan {
            // Unplanned training: the activities that land in the inbox with no
            // obvious match, which is the case worth reviewing by hand.
            let strayCount = shape == .looselyRelated ? 6 : 3
            for index in 0..<strayCount {
                let dayOffset = Int(rng.next(upTo: UInt64(max(1, dayCount))))
                guard let day = calendar.date(byAdding: .day, value: -dayOffset, to: now) else { continue }
                let hour = 6 + Int(rng.next(upTo: 12))
                let start = calendar.date(bySettingHour: hour, minute: Int(rng.next(upTo: 60)),
                                          second: 0, of: day) ?? day
                let sport: Sport = [.run, .bike, .swim][index % 3]
                let minutes = 20 + Int(rng.next(upTo: 70))
                results.append(session(sport: sport, start: start, minutes: minutes,
                                       plannedDistance: nil, rng: &rng))
            }
        }

        return results.sorted { $0.start < $1.start }
    }

    /// Only sports HealthKit can represent are seeded; strength and mobility are
    /// filed as their own types by real apps but are not useful here.
    private func importableSport(for sport: Sport) -> Sport? {
        switch sport {
        case .swim, .bike, .run: return sport
        // A brick is recorded by most devices as its dominant leg.
        case .brick: return .bike
        case .race: return .run
        case .strength, .mobility, .recovery: return nil
        }
    }

    /// Plausible pace, heart rate and energy for the sport — no impossible
    /// values, because a matcher tuned against nonsense proves nothing.
    private func session(
        sport: Sport, start: Date, minutes: Int,
        plannedDistance: Double?, rng: inout SeededGenerator
    ) -> SeededWorkout {
        let seconds = minutes * 60
        let hours = Double(seconds) / 3600

        let speedMetresPerSecond: Double
        switch sport {
        case .run: speedMetresPerSecond = 2.6 + Double(rng.next(upTo: 12)) / 10   // ~4:15–6:25/km
        case .bike: speedMetresPerSecond = 6.5 + Double(rng.next(upTo: 30)) / 10  // ~23–34 km/h
        case .swim: speedMetresPerSecond = 0.9 + Double(rng.next(upTo: 5)) / 10   // ~1:45–2:20/100m
        default: speedMetresPerSecond = 2.0
        }

        let distance = plannedDistance.map { $0 * (0.92 + Double(rng.next(upTo: 16)) / 100) }
            ?? (speedMetresPerSecond * Double(seconds))

        let heartRate: Double
        switch sport {
        case .run: heartRate = 138 + Double(rng.next(upTo: 26))
        case .bike: heartRate = 128 + Double(rng.next(upTo: 28))
        case .swim: heartRate = 125 + Double(rng.next(upTo: 20))
        default: heartRate = 120
        }

        // Rough but plausible energy; never precise-looking.
        let kcalPerHour: Double = sport == .bike ? 640 : (sport == .swim ? 520 : 700)
        let energy = (kcalPerHour * hours).rounded()

        return SeededWorkout(
            sport: sport, start: start, durationSeconds: seconds,
            distanceMeters: distance.rounded(),
            activeEnergyKilocalories: energy,
            averageHeartRate: heartRate.rounded(),
            isIndoor: sport == .bike ? (rng.next(upTo: 100) < 35) : false,
            isOpenWater: sport == .swim ? (rng.next(upTo: 100) < 25) : nil)
    }
}

/// Small deterministic PRNG so a seeded run is exactly reproducible. Not for
/// anything security-related — it exists so a failing import can be replayed.
struct SeededGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }

    mutating func next(upTo bound: UInt64) -> UInt64 {
        bound == 0 ? 0 : next() % bound
    }
}
