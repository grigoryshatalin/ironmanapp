import XCTest
import WorkoutKit
import EnduranceDomain
import EnduranceTrainingPlans
@testable import EnduranceWorkoutKit
@testable import Endurance

/// Does WorkoutKit actually accept what the converter produces?
///
/// Every other WorkoutKit test uses a fake scheduler, so it verifies our policy
/// and never the framework's opinion of it. That gap is why a conversion could
/// be `.exact` — reported in the UI as ready to send — and still be refused at
/// the moment it was handed to WorkoutKit. This asks the real framework.
final class WorkoutKitFrameworkAcceptanceTests: XCTestCase {

    private func requests() throws -> [(ScheduledWorkout, WorkoutKitScheduleRequest)] {
        let plan = try BundledPlans.load36Week()
        var comps = DateComponents(); comps.year = 2026; comps.month = 3; comps.day = 2
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let config = ScheduleConfiguration(
            anchor: .startDate(cal.date(from: comps)!), timeZoneIdentifier: "UTC")
        let schedule = try ScheduleEngine().generateSchedule(plan: plan, config: config)
        let templates = Dictionary(
            uniqueKeysWithValues: plan.weeks.flatMap { $0.days }.flatMap { $0.workouts }.map { ($0.id, $0) })
        let converter = WorkoutKitConverter()

        func template(_ w: ScheduledWorkout) -> WorkoutTemplate? {
            w.identity.templateID.flatMap { templates[$0] }
        }
        // Bricks and races convert as multisport containers, exactly as the
        // coordinator does. Testing the per-row conversion instead would leave
        // `SwimBikeRunWorkout` — and `supportsActivityOrdering` — unexercised.
        func grouped(_ workout: ScheduledWorkout) -> WorkoutKitConversionResult {
            if workout.sport == .race {
                return converter.convertRace(workout, template: template(workout))
            }
            if let groupID = workout.brickGroupID {
                let components = schedule
                    .filter { $0.brickGroupID == groupID }
                    .sorted { ($0.plannedStart, $0.order) < ($1.plannedStart, $1.order) }
                    .map { (workout: $0, template: template($0)) }
                if components.count >= 2,
                   let result = converter.convertMultisport(
                       components: components,
                       displayName: components.map(\.workout.title).joined(separator: " + ")) {
                    return result
                }
            }
            return converter.convert(workout, template: template(workout))
        }

        return schedule.compactMap { workout in
            let conversion = grouped(workout)
            guard conversion.outcome.isSchedulable else { return nil }
            return (workout, WorkoutKitScheduleRequest(
                workoutPlanID: UUID(),
                scheduledWorkoutID: workout.id,
                plannedStart: workout.plannedStart,
                conversion: conversion))
        }
    }

    /// The load-bearing assertion: anything we tell the athlete is schedulable
    /// must survive being turned into a real `WorkoutPlan`.
    func testEverySchedulableConversionIsAcceptedByWorkoutKit() throws {
        let adapter = WorkoutKitSchedulerAdapter()
        var failures: [String: [String]] = [:]

        for (workout, request) in try requests() {
            do {
                _ = try adapter.makePlan(from: request)
            } catch {
                let reason = "\(error)"
                failures[reason, default: []].append("\(workout.sport)/\(workout.title)")
            }
        }

        if !failures.isEmpty {
            for (reason, items) in failures.sorted(by: { $0.value.count > $1.value.count }) {
                print("REJECTED \(items.count)x — \(reason)")
                for item in Set(items).sorted().prefix(4) { print("    \(item)") }
            }
        }
        XCTAssertTrue(failures.isEmpty,
                      "WorkoutKit refused \(failures.values.map(\.count).reduce(0, +)) conversions we reported as schedulable")
    }

    /// Narrower, so a failure names the cause directly rather than by count.
    func testFrameworkSupportsTheActivitiesWeEmit() {
        XCTAssertTrue(CustomWorkout.supportsActivity(.running))
        XCTAssertTrue(CustomWorkout.supportsActivity(.cycling))
        XCTAssertTrue(CustomWorkout.supportsActivity(.swimming))
        XCTAssertTrue(CustomWorkout.supportsActivity(.highIntensityIntervalTraining),
                      "strength is scheduled as HIIT; if this fails, that mapping is invalid")
        XCTAssertTrue(CustomWorkout.supportsActivity(.functionalStrengthTraining),
                      "continuous mobility is scheduled as functional strength training")
    }

    /// A brick is bike then run — a subset of triathlon order, not the full
    /// swim/bike/run. If WorkoutKit rejects that ordering, every brick in the
    /// plan silently stops converting, so this is asserted rather than assumed.
    func testFrameworkAcceptsABikeThenRunBrickOrdering() {
        XCTAssertTrue(
            SwimBikeRunWorkout.supportsActivityOrdering([.cycling(.outdoor), .running(.outdoor)]),
            "a bike-to-run brick must be a valid multisport ordering")
    }

    func testFrameworkAcceptsFullTriathlonOrdering() {
        XCTAssertTrue(
            SwimBikeRunWorkout.supportsActivityOrdering(
                [.swimming(.openWater), .cycling(.outdoor), .running(.outdoor)]),
            "race day is swim, bike, run")
    }
}
