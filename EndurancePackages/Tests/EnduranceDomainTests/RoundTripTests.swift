import Testing
import Foundation
@testable import EnduranceDomain

@Suite("Export / import round trips & deterministic ids")
struct RoundTripTests {
    let engine = ScheduleEngine()

    @Test("A plan survives encode → decode unchanged and stays valid")
    func planRoundTrip() throws {
        let plan = SamplePlan.plan(weeks: 3)
        let data = try PlanCodec.encode(plan)
        let decoded = try PlanCodec.decode(data)
        #expect(decoded == plan)
        #expect(PlanValidator().validate(decoded).isValid)
    }

    @Test("A malformed plan yields an actionable error, not a crash")
    func malformedPlan() {
        let bad = Data(#"{ "name": "oops" }"#.utf8)
        #expect(throws: PlanCodec.DecodeFailure.self) {
            _ = try PlanCodec.decode(bad)
        }
    }

    @Test("Training history survives encode → decode unchanged")
    func historyRoundTrip() throws {
        let plan = SamplePlan.plan(weeks: 2)
        let config = SamplePlan.config(start: TestDates.date(2026, 4, 6, tz: "UTC"), tz: "UTC")
        var schedule = try engine.generateSchedule(plan: plan, config: config)
        // Add some user state so the round-trip exercises completion/modifications.
        schedule[0].status = .completed
        schedule[0].completion = WorkoutCompletion(completedAt: schedule[0].plannedStart, actualDurationMinutes: 32, perceivedExertion: 4, source: .manual)
        schedule[1].modifications = [PlanModification(type: .shorten, createdAt: schedule[1].plannedStart, oldDurationMinutes: 60, newDurationMinutes: 40, reason: "time-crunched")]

        let export = TrainingHistoryExport(
            exportedAt: TestDates.date(2026, 4, 20, 12, 0, tz: "UTC"),
            planID: plan.id,
            scheduleConfiguration: config,
            notificationPreferences: NotificationPreferences(enabledCategories: [.workout, .weeklyReview]),
            units: .mixedTriathlon,
            scheduledWorkouts: schedule)

        let data = try ExportService.encode(export)
        let decoded = try ExportService.decode(data)
        #expect(decoded == export)
    }

    @Test("Completion CSV escapes commas and quotes and includes done sessions")
    func csv() throws {
        let base = TestDates.date(2026, 6, 1, tz: "UTC")
        var w = ScheduledFactory.make(name: "Long, hard \"ride\"", sport: .bike, stress: .long, start: base, durationMinutes: 120)
        w.status = .completed
        w.completion = WorkoutCompletion(completedAt: base, actualDurationMinutes: 118, actualDistanceMeters: 40000, perceivedExertion: 6, notes: "felt, good", source: .appleWatch)
        let csv = ExportService.completionCSV([w])
        let lines = csv.split(separator: "\n")
        #expect(lines.count == 2)
        #expect(csv.contains("\"Long, hard \"\"ride\"\"\"")) // quote-escaped
        #expect(csv.contains("appleWatch"))
    }

    @Test("UUIDv5 matches the RFC 4122 DNS namespace test vector")
    func uuidV5Vector() {
        let dns = UUID(uuidString: "6ba7b810-9dad-11d1-80b4-00c04fd430c8")!
        let uuid = UUIDv5.make(namespace: dns, name: "www.example.com")
        #expect(uuid.uuidString.lowercased() == "2ed6657d-e927-568b-95e1-2665a8aea6a2")
    }

    @Test("UUIDv5 is deterministic and namespace-separated")
    func uuidV5Determinism() {
        let a = UUIDv5.make(namespace: UUIDv5.Namespace.enduranceSchedule, name: "x")
        let b = UUIDv5.make(namespace: UUIDv5.Namespace.enduranceSchedule, name: "x")
        let c = UUIDv5.make(namespace: UUIDv5.Namespace.enduranceNotification, name: "x")
        #expect(a == b)
        #expect(a != c)
    }
}
