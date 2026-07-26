import Testing
import Foundation
@testable import EnduranceDomain
@testable import EnduranceTrainingPlans

/// §I — the conversion policy must work against the *real* plan, not just
/// hand-built fixtures.
///
/// This exists because of a defect found in Stage 4: every supplemental
/// disclosure was treated as a simplification, and since 34 of the first 60
/// bundled sessions carry technique cues, nothing ever scheduled automatically.
/// The feature was technically correct and practically useless. These tests fail
/// if that returns.
@Suite("Bundled plan WorkoutKit conversion")
struct BundledPlanConversionTests {

    private func convertEarlySessions(limit: Int = 60) throws -> [WorkoutKitConversionResult] {
        let plan = try BundledPlans.load36Week()
        let config = ScheduleConfiguration(
            anchor: .startDate(TestDates.date(2026, 3, 2, tz: "UTC")),
            timeZoneIdentifier: "UTC")
        let schedule = try ScheduleEngine().generateSchedule(plan: plan, config: config)
        let templates = Dictionary(
            uniqueKeysWithValues: plan.weeks.flatMap { $0.days }.flatMap { $0.workouts }.map { ($0.id, $0) })
        let converter = WorkoutKitConverter()
        return schedule.prefix(limit).map { workout in
            converter.convert(workout, template: workout.identity.templateID.flatMap { templates[$0] })
        }
    }

    @Test("A meaningful share of real sessions schedule without asking")
    func realPlanProducesExactConversions() throws {
        let results = try convertEarlySessions()
        let exact = results.filter { $0.outcome == .exact }

        #expect(!exact.isEmpty,
                "if nothing converts exactly, enabling Apple Workout appears to do nothing")
        #expect(exact.count >= 10,
                "expected a usable number of automatically schedulable sessions, got \(exact.count)")
    }

    @Test("Swim, bike and run sessions are representable")
    func coreSportsAreRepresentable() throws {
        let results = try convertEarlySessions()
        for sport in [Sport.swim, .bike, .run] {
            let forSport = results.filter { $0.sport == sport }
            guard !forSport.isEmpty else { continue }
            #expect(forSport.contains { $0.outcome.isSchedulable },
                    "\(sport) sessions should be schedulable in some form")
        }
    }

    @Test("Sessions that cannot be represented say so rather than converting badly")
    func unsupportedSessionsAreExplicit() throws {
        let results = try convertEarlySessions()
        let unsupported = results.filter { $0.outcome == .unsupported }
        #expect(!unsupported.isEmpty, "strength and mobility genuinely cannot map")
        #expect(unsupported.allSatisfy { !$0.unsupportedReasons.isEmpty },
                "every refusal must carry a stated reason")
        #expect(unsupported.allSatisfy { $0.representation == nil },
                "an unsupported conversion must not carry a partial representation")
    }

    @Test("Every conversion is internally consistent")
    func resultsAreConsistent() throws {
        for result in try convertEarlySessions() {
            switch result.outcome {
            case .exact:
                #expect(result.automaticSchedulingAllowed)
                #expect(!result.requiresUserConfirmation)
                #expect(result.representation != nil)
            case .simplified:
                #expect(!result.automaticSchedulingAllowed)
                #expect(result.requiresUserConfirmation)
                #expect(result.representation != nil)
                #expect(result.warnings.contains { $0.isStructural })
            case .unsupported:
                #expect(!result.automaticSchedulingAllowed)
                #expect(result.representation == nil)
            }
        }
    }
}
