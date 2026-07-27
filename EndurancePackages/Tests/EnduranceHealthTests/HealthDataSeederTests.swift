import Testing
import Foundation
@testable import EnduranceHealth
@testable import EnduranceDomain

/// The seeder exists to produce *believable* test data. Data that is too tidy
/// would let the matcher pass by accident — every session lining up perfectly
/// proves nothing about the ambiguous cases the Health Inbox exists for.
@Suite("Health data seeding")
struct HealthDataSeederTests {

    private let now = Date(timeIntervalSince1970: 1_770_000_000)

    /// Built inline: `ScheduledFactory` belongs to the domain test target.
    private func planned(count: Int, sport: Sport = .run) -> [ScheduledWorkout] {
        (0..<count).map { index in
            let start = now.addingTimeInterval(TimeInterval(-index * 24 * 3600))
            return ScheduledWorkout(
                identity: WorkoutIdentity(
                    scheduledWorkoutID: UUIDv5.make(
                        namespace: UUIDv5.Namespace.enduranceSchedule,
                        name: "seed-planned-\(sport.rawValue)-\(index)")),
                weekNumber: 1,
                weekdayOffset: index % 7,
                dayIndex: index,
                order: 0,
                sport: sport,
                title: "Planned \(index)",
                objective: "Objective",
                plannedDurationMinutes: 60,
                plannedDistanceMeters: 10_000,
                intensity: .endurance,
                stressCategory: .moderate,
                originalDate: start,
                scheduledDate: start,
                plannedStart: start,
                status: .planned)
        }
    }

    // MARK: - Determinism

    @Test("The same seed reproduces the same history exactly")
    func deterministic() {
        let plan = HealthSeedPlan(seed: 99)
        let a = plan.build(relativeTo: now, planned: planned(count: 10))
        let b = plan.build(relativeTo: now, planned: planned(count: 10))

        #expect(a.count == b.count)
        #expect(zip(a, b).allSatisfy {
            $0.start == $1.start && $0.durationSeconds == $1.durationSeconds
                && $0.distanceMeters == $1.distanceMeters
        }, "a failing import must be reproducible from its seed")
    }

    @Test("Different seeds produce different histories")
    func seedsDiffer() {
        let a = HealthSeedPlan(seed: 1).build(relativeTo: now, planned: planned(count: 10))
        let b = HealthSeedPlan(seed: 2).build(relativeTo: now, planned: planned(count: 10))
        #expect(a.map(\.start) != b.map(\.start))
    }

    // MARK: - Realism

    @Test("Not every planned session is completed — a perfect record is not realistic")
    func someSessionsAreMissed() {
        let plan = HealthSeedPlan(shape: .matchingPlan, dayCount: 14, seed: 7)
        let sessions = plan.build(relativeTo: now, planned: planned(count: 14))
        #expect(sessions.count < 14,
                "seeding a 100% completion rate would never exercise unmatched sessions")
        #expect(!sessions.isEmpty)
    }

    @Test("Sessions start near their planned time but never exactly on it")
    func startTimesAreOffset() {
        let plan = HealthSeedPlan(shape: .matchingPlan, seed: 3)
        let scheduled = planned(count: 12)
        let sessions = plan.build(relativeTo: now, planned: scheduled)

        let plannedStarts = Set(scheduled.map(\.plannedStart))
        let exactHits = sessions.filter { plannedStarts.contains($0.start) }
        #expect(exactHits.isEmpty,
                "real workouts never start on the exact planned second")

        // But they should be close enough to be matchable.
        for session in sessions {
            let nearest = scheduled.map { abs($0.plannedStart.timeIntervalSince(session.start)) }.min() ?? .infinity
            #expect(nearest <= 60 * 60, "a matching-plan session should stay within an hour")
        }
    }

    @Test("Durations vary around the plan rather than matching it exactly")
    func durationsVary() {
        let sessions = HealthSeedPlan(shape: .matchingPlan, seed: 11)
            .build(relativeTo: now, planned: planned(count: 12))
        let distinct = Set(sessions.map(\.durationSeconds))
        #expect(distinct.count > 1, "identical durations would be unrealistically tidy")
    }

    @Test("Paces are physiologically plausible for each sport")
    func pacesArePlausible() {
        let sessions = HealthSeedPlan(shape: .realistic, dayCount: 21, seed: 5)
            .build(relativeTo: now, planned: planned(count: 20, sport: .run))

        for session in sessions {
            guard let distance = session.distanceMeters, distance > 0 else { continue }
            let speed = distance / Double(session.durationSeconds)
            switch session.sport {
            case .run:
                #expect(speed > 1.5 && speed < 6.0, "run speed \(speed) m/s is implausible")
            case .bike:
                #expect(speed > 3.0 && speed < 16.0, "bike speed \(speed) m/s is implausible")
            case .swim:
                #expect(speed > 0.4 && speed < 2.5, "swim speed \(speed) m/s is implausible")
            default: break
            }
        }
    }

    @Test("Heart rates sit in a believable working range")
    func heartRatesArePlausible() {
        let sessions = HealthSeedPlan(seed: 13).build(relativeTo: now, planned: planned(count: 15))
        for session in sessions {
            guard let hr = session.averageHeartRate else { continue }
            #expect(hr > 100 && hr < 190, "average heart rate \(hr) is implausible")
        }
    }

    @Test("Only sports HealthKit represents are seeded")
    func onlyRepresentableSports() {
        let mixed = [Sport.strength, .mobility, .recovery].flatMap { sport in
            planned(count: 4, sport: sport)
        }
        let sessions = HealthSeedPlan(shape: .matchingPlan, seed: 17)
            .build(relativeTo: now, planned: mixed)
        #expect(sessions.allSatisfy { [.swim, .bike, .run].contains($0.sport) })
    }

    @Test("Every seeded session has a real activity mapping")
    func everySessionMaps() {
        let sessions = HealthSeedPlan(seed: 21).build(relativeTo: now, planned: planned(count: 12))
        for session in sessions {
            #expect(HealthActivityMapping.activityRawValue(for: session.sport) != nil,
                    "\(session.sport) cannot be written to HealthKit")
        }
    }

    // MARK: - Shapes

    @Test("A loosely related shape produces unplanned training for the inbox")
    func looselyRelatedProducesStrays() {
        let sessions = HealthSeedPlan(shape: .looselyRelated, seed: 23)
            .build(relativeTo: now, planned: planned(count: 10))
        #expect(!sessions.isEmpty)
        // None should coincide tightly with a planned session.
        let scheduled = planned(count: 10)
        for session in sessions {
            let nearest = scheduled.map { abs($0.plannedStart.timeIntervalSince(session.start)) }.min() ?? .infinity
            #expect(nearest > 60, "loosely related data should not land on the plan")
        }
    }

    @Test("Seeded sessions are ordered and fall inside the requested window")
    func withinWindow() {
        let days = 10
        let sessions = HealthSeedPlan(dayCount: days, seed: 29)
            .build(relativeTo: now, planned: planned(count: days))
        #expect(sessions == sessions.sorted { $0.start < $1.start })
        let earliest = now.addingTimeInterval(TimeInterval(-(days + 1) * 24 * 3600))
        #expect(sessions.allSatisfy { $0.start >= earliest && $0.start <= now.addingTimeInterval(3600) })
    }

    @Test("Durations and end times are internally consistent")
    func endTimesConsistent() {
        for session in HealthSeedPlan(seed: 31).build(relativeTo: now, planned: planned(count: 10)) {
            #expect(session.end == session.start.addingTimeInterval(TimeInterval(session.durationSeconds)))
            #expect(session.durationSeconds >= HealthImportFilter.minimumDurationSeconds,
                    "a seeded session shorter than the import floor would be silently discarded")
        }
    }

    // MARK: - Integration with the import pipeline

    /// The point of the seeder: data that flows through the real matcher and
    /// produces a usable mix of outcomes rather than all-or-nothing.
    @Test("Seeded data produces a realistic spread of match confidences")
    func producesUsefulMatchSpread() {
        let scheduled = planned(count: 14)
        let seeded = HealthSeedPlan(shape: .realistic, dayCount: 14, seed: 37)
            .build(relativeTo: now, planned: scheduled)

        let matcher = WorkoutMatcher()
        var confidences: [WorkoutMatcher.Confidence: Int] = [:]

        for session in seeded {
            let summary = ExternalWorkoutSummary(
                provider: .healthKit,
                providerWorkoutID: session.id.uuidString,
                sourceBundleIdentifier: "com.apple.health",
                sport: session.sport,
                start: session.start,
                end: session.end,
                durationSeconds: session.durationSeconds,
                distanceMeters: session.distanceMeters,
                importedAt: now,
                lastObservedAt: now)
            let match = matcher.match(summary, against: scheduled)
            confidences[match.confidence, default: 0] += 1
        }

        #expect(!confidences.isEmpty)
        #expect(confidences.keys.count > 1,
                "seeded data that produced a single outcome would not exercise the inbox")
    }
}
