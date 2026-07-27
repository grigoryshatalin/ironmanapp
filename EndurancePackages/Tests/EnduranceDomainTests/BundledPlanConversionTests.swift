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


    /// Every session of one sport across the whole plan, not just the first 60.
    private func convertAll(sport: Sport) throws -> [WorkoutKitConversionResult] {
        let plan = try BundledPlans.load36Week()
        let config = ScheduleConfiguration(
            anchor: .startDate(TestDates.date(2026, 3, 2, tz: "UTC")),
            timeZoneIdentifier: "UTC")
        let schedule = try ScheduleEngine().generateSchedule(plan: plan, config: config)
        let templates = Dictionary(
            uniqueKeysWithValues: plan.weeks.flatMap { $0.days }.flatMap { $0.workouts }.map { ($0.id, $0) })
        let converter = WorkoutKitConverter()
        return schedule.filter { $0.sport == sport }.map { workout in
            converter.convert(workout, template: workout.identity.templateID.flatMap { templates[$0] })
        }
    }

    /// Strength must reach the Watch.
    ///
    /// Strength was previously "unsupported — no honest equivalent", so those
    /// sessions silently never reached the Watch at all. They are now filed as
    /// HIIT: an approximation, but one the athlete can start and complete.
    @Test("Every strength session converts to a schedulable workout")
    func strengthSchedulesAsHIIT() throws {
        let results = try convertAll(sport: .strength)
        let unschedulable = results.filter { !$0.outcome.isSchedulable }.count
        #expect(!results.isEmpty, "the bundled plan must contain strength work")
        #expect(unschedulable == 0, "strength must be schedulable; \(unschedulable) were not")
    }

    /// Mobility and recovery stay unsupported deliberately, so this fails if
    /// someone later maps them by reflex rather than by decision.
    @Test("Mobility remains deliberately unscheduled")
    func mobilityStaysUnsupported() throws {
        let results = try convertAll(sport: .mobility)
        let scheduled = results.filter { $0.outcome != .unsupported }.count
        #expect(!results.isEmpty)
        #expect(scheduled == 0, "mobility carries no interval structure worth sending to the Watch")
    }

    /// Not an assertion so much as a published number: how much of the real plan
    /// can actually reach the Watch. Printed so a policy change is visible as a
    /// coverage change rather than an opinion.
    @Test("Report Watch coverage across the whole plan")
    func reportCoverage() throws {
        let plan = try BundledPlans.load36Week()
        let config = ScheduleConfiguration(
            anchor: .startDate(TestDates.date(2026, 3, 2, tz: "UTC")),
            timeZoneIdentifier: "UTC")
        let schedule = try ScheduleEngine().generateSchedule(plan: plan, config: config)
        let templates = Dictionary(
            uniqueKeysWithValues: plan.weeks.flatMap { $0.days }.flatMap { $0.workouts }.map { ($0.id, $0) })
        let converter = WorkoutKitConverter()

        var counts: [WorkoutKitConversionOutcome: Int] = [:]
        var bySport: [Sport: (schedulable: Int, total: Int)] = [:]
        for w in schedule {
            let r = converter.convert(w, template: w.identity.templateID.flatMap { templates[$0] })
            counts[r.outcome, default: 0] += 1
            var entry = bySport[w.sport] ?? (0, 0)
            entry.total += 1
            if r.outcome.isSchedulable { entry.schedulable += 1 }
            bySport[w.sport] = entry
        }
        let schedulable = schedule.count - (counts[.unsupported] ?? 0)
        print("WATCH COVERAGE: \(schedulable)/\(schedule.count) sessions schedulable")
        print("  exact \(counts[.exact] ?? 0), simplified \(counts[.simplified] ?? 0), unsupported \(counts[.unsupported] ?? 0)")
        for (sport, e) in bySport.sorted(by: { "\($0.key)" < "\($1.key)" }) {
            print("  \(sport): \(e.schedulable)/\(e.total)")
        }
        // Why each refusal happened, per sport — so "unsupported" is always
        // attributable to a named reason rather than a mystery.
        var reasons: [String: Int] = [:]
        for w in schedule {
            let r = converter.convert(w, template: w.identity.templateID.flatMap { templates[$0] })
            for reason in r.unsupportedReasons {
                reasons["\(w.sport)/\(reason.rawValue)", default: 0] += 1
            }
        }
        print("REFUSAL REASONS:")
        for (k, v) in reasons.sorted(by: { $0.key < $1.key }) { print("  \(k): \(v)") }
        #expect(schedulable > 0)
    }

    /// Guards the plan *data*, not the converter.
    ///
    /// 35 swims were unschedulable because a "20 s rest" recovery step carried
    /// `durationSeconds: 0` — the duration existed only in the human-readable
    /// label. The converter was right to refuse (inventing a duration would put
    /// a wrong interval on someone's wrist); the plan was wrong to omit it. A
    /// single such step fails an entire workout, so this is cheap to get wrong
    /// and expensive to notice.
    @Test("Every leaf step in the bundled plan states a goal it can be converted from")
    func everyLeafStepHasAGoal() throws {
        let plan = try BundledPlans.load36Week()

        func leaves(_ steps: [WorkoutStep]) -> [WorkoutStep] {
            steps.flatMap { $0.childSteps.isEmpty ? [$0] : leaves($0.childSteps) }
        }

        var offenders: [String] = []
        for week in plan.weeks {
            for day in week.days {
                for template in day.workouts {
                    let all = leaves(template.warmup) + leaves(template.mainSet) + leaves(template.cooldown)
                    for step in all {
                        let hasDuration = (step.durationSeconds ?? 0) > 0
                        let hasDistance = (step.distanceMeters ?? 0) > 0
                        // A transition legitimately has no goal of its own; it is
                        // part of a brick, which is refused for its own reason.
                        guard step.kind != .transition else { continue }
                        if !hasDuration && !hasDistance && !step.isOpenGoal {
                            offenders.append("w\(week.weekNumber) \(template.title): '\(step.label ?? "—")'")
                        }
                    }
                }
            }
        }
        #expect(offenders.isEmpty,
                "steps with no duration, distance or open goal cannot be sent to the Watch: \(offenders.prefix(5))")
    }

}
