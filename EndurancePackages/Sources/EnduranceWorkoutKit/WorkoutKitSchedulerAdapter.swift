import Foundation
import EnduranceDomain

/// The real WorkoutKit boundary. Framework construction is intentionally here,
/// after the pure converter has already made its fidelity decision.
#if canImport(WorkoutKit) && canImport(HealthKit)
import WorkoutKit
import HealthKit

@available(iOS 17.0, watchOS 10.0, macOS 15.0, *)
public final class WorkoutKitSchedulerAdapter: @unchecked Sendable, WorkoutScheduling {
    private let scheduler: WorkoutScheduler

    public init(scheduler: WorkoutScheduler = .shared) {
        self.scheduler = scheduler
    }

    public var isSupported: Bool { WorkoutScheduler.isSupported }

    public func authorizationState() async -> WorkoutSchedulingAuthorization {
        map(await scheduler.authorizationState)
    }

    public func requestAuthorization() async -> WorkoutSchedulingAuthorization {
        map(await scheduler.requestAuthorization())
    }

    public func schedule(_ request: WorkoutKitScheduleRequest) async throws {
        guard isSupported else { throw WorkoutKitSchedulingError.workoutKitUnavailable }
        guard await authorizationState() == .authorized else {
            let state = await authorizationState()
            throw state == .denied
                ? WorkoutKitSchedulingError.authorizationDenied
                : WorkoutKitSchedulingError.authorizationRequired
        }
        let date = dateComponents(for: request.plannedStart)
        let existing = await scheduler.scheduledWorkouts
        if existing.contains(where: { matches($0, planID: request.workoutPlanID, slot: date) }) {
            return // Idempotent repeated synchronization.
        }
        let plan = try makePlan(from: request)
        await scheduler.schedule(plan, at: date)
        let reconciled = await scheduler.scheduledWorkouts
        guard reconciled.contains(where: { matches($0, planID: request.workoutPlanID, slot: date) }) else {
            throw WorkoutKitSchedulingError.scheduleFailed
        }
    }

    public func remove(_ request: WorkoutKitScheduleRequest) async throws {
        guard isSupported else { throw WorkoutKitSchedulingError.workoutKitUnavailable }
        let date = dateComponents(for: request.plannedStart)
        let existing = await scheduler.scheduledWorkouts
        guard existing.contains(where: { matches($0, planID: request.workoutPlanID, slot: date) }) else {
            return // It is already absent: removal is idempotent.
        }
        let plan = try makePlan(from: request)
        await scheduler.remove(plan, at: date)
        let reconciled = await scheduler.scheduledWorkouts
        guard !reconciled.contains(where: { matches($0, planID: request.workoutPlanID, slot: date) }) else {
            throw WorkoutKitSchedulingError.removalFailed
        }
    }

    public func scheduledPlans() async throws -> [WorkoutKitScheduledPlan] {
        guard isSupported else { throw WorkoutKitSchedulingError.workoutKitUnavailable }
        return await scheduler.scheduledWorkouts.compactMap { scheduled in
            guard let date = Calendar.current.date(from: scheduled.date) else { return nil }
            return WorkoutKitScheduledPlan(
                workoutPlanID: scheduled.plan.id, plannedStart: date, isComplete: scheduled.complete)
        }
    }

    public func removeAllEndurancePlans() async throws {
        guard isSupported else { throw WorkoutKitSchedulingError.workoutKitUnavailable }
        await scheduler.removeAllWorkouts()
        guard await scheduler.scheduledWorkouts.isEmpty else {
            throw WorkoutKitSchedulingError.removalFailed
        }
    }

    // MARK: - Framework mapping

    /// Internal rather than private so tests can ask the *real* framework
    /// whether every representation the converter produces is actually
    /// acceptable. Simulator-only, since WorkoutKit does not exist on macOS.
    func makePlan(from request: WorkoutKitScheduleRequest) throws -> WorkoutPlan {
        guard let representation = request.conversion.representation else {
            throw WorkoutKitSchedulingError.conversionUnsupported
        }
        let workout: WorkoutPlan.Workout
        switch representation {
        case let .singleGoal(activity, location, goal):
            let activityType = activityType(for: activity)
            let frameworkGoal = try goalValue(goal)
            guard SingleGoalWorkout.supportsActivity(activityType),
                  SingleGoalWorkout.supportsGoal(frameworkGoal, activity: activityType,
                                                location: sessionLocation(for: location)) else {
                throw WorkoutKitSchedulingError.unsupportedGoal
            }
            workout = .goal(SingleGoalWorkout(
                activity: activityType,
                location: sessionLocation(for: location),
                swimmingLocation: swimmingLocation(for: location),
                goal: frameworkGoal))

        case let .custom(activity, location, displayName, warmup, blocks, cooldown):
            let activityType = activityType(for: activity)
            let sessionLocation = sessionLocation(for: location)
            guard CustomWorkout.supportsActivity(activityType) else {
                throw WorkoutKitSchedulingError.invalidWorkoutStructure
            }
            let frameworkWarmup = try warmup.map { try stepValue($0, activity: activityType, location: sessionLocation) }
            let frameworkCooldown = try cooldown.map { try stepValue($0, activity: activityType, location: sessionLocation) }
            let frameworkBlocks = try blocks.map { block in
                IntervalBlock(steps: try block.steps.map { step in
                    guard let purpose = step.purpose else { throw WorkoutKitSchedulingError.invalidWorkoutStructure }
                    return IntervalStep(intervalPurpose(for: purpose),
                                        step: try stepValue(step, activity: activityType, location: sessionLocation))
                }, iterations: block.iterations)
            }
            workout = .custom(CustomWorkout(
                activity: activityType, location: sessionLocation, displayName: displayName,
                warmup: frameworkWarmup, blocks: frameworkBlocks, cooldown: frameworkCooldown))

        case let .swimBikeRun(activities, displayName):
            let frameworkActivities = activities.map(multisportActivity)
            guard SwimBikeRunWorkout.supportsActivityOrdering(frameworkActivities) else {
                throw WorkoutKitSchedulingError.unsupportedMultisport
            }
            workout = .swimBikeRun(SwimBikeRunWorkout(activities: frameworkActivities, displayName: displayName))
        }
        return WorkoutPlan(workout, id: request.workoutPlanID)
    }

    private func stepValue(
        _ step: WorkoutKitStepRepresentation,
        activity: HKWorkoutActivityType,
        location: HKWorkoutSessionLocationType
    ) throws -> WorkoutKit.WorkoutStep {
        let goal = try goalValue(step.goal)
        guard CustomWorkout.supportsGoal(goal, activity: activity, location: location) else {
            throw WorkoutKitSchedulingError.unsupportedGoal
        }
        let alert = try alertValue(step.alert, activity: activity, location: location)
        // iOS 18 is our minimum deployment target; WorkoutKit's custom step
        // names are available here. Endurance labels and RPE remain text only.
        return WorkoutKit.WorkoutStep(goal: goal, alert: alert, displayName: stepDisplayName(step))
    }

    private func goalValue(_ goal: WorkoutKitGoalRepresentation) throws -> WorkoutKit.WorkoutGoal {
        switch goal {
        case .open: return .open
        case let .time(seconds):
            guard seconds > 0 else { throw WorkoutKitSchedulingError.unsupportedGoal }
            return .time(Double(seconds), .seconds)
        case let .distance(metres):
            guard metres > 0 else { throw WorkoutKitSchedulingError.unsupportedGoal }
            return .distance(metres, .meters)
        case let .poolDistanceWithTime(metres, seconds):
            guard metres > 0, seconds > 0 else { throw WorkoutKitSchedulingError.unsupportedGoal }
            return .poolSwimDistanceWithTime(
                Measurement(value: metres, unit: .meters),
                Measurement(value: Double(seconds), unit: .seconds))
        }
    }

    private func alertValue(
        _ alert: WorkoutKitAlertRepresentation?,
        activity: HKWorkoutActivityType,
        location: HKWorkoutSessionLocationType
    ) throws -> (any WorkoutAlert)? {
        guard let alert else { return nil }
        let value: any WorkoutAlert
        switch alert {
        case let .heartRate(bpm):
            value = HeartRateRangeAlert(target: Measurement(value: bpm.lowerBound, unit: WorkoutAlertMetric.countPerMinute)...Measurement(value: bpm.upperBound, unit: WorkoutAlertMetric.countPerMinute))
        case let .speed(metresPerSecond):
            value = SpeedRangeAlert(target: Measurement(value: metresPerSecond.lowerBound, unit: .metersPerSecond)...Measurement(value: metresPerSecond.upperBound, unit: .metersPerSecond), metric: .current)
        case let .power(watts):
            value = PowerRangeAlert(target: Measurement(value: watts.lowerBound, unit: .watts)...Measurement(value: watts.upperBound, unit: .watts), metric: .current)
        case let .cadence(rpm):
            value = CadenceRangeAlert(target: Measurement(value: rpm.lowerBound, unit: WorkoutAlertMetric.countPerMinute)...Measurement(value: rpm.upperBound, unit: WorkoutAlertMetric.countPerMinute))
        }
        guard CustomWorkout.supportsAlert(value, activity: activity, location: location) else {
            throw WorkoutKitSchedulingError.unsupportedAlert
        }
        return value
    }

    private func stepDisplayName(_ step: WorkoutKitStepRepresentation) -> String? {
        let rpe = step.perceivedExertionRange.map {
            String(localized: "RPE \($0.lowerBound)–\($0.upperBound)")
        }
        return [step.displayName, rpe].compactMap { $0 }.joined(separator: " · ").nilIfEmpty
    }

    private func activityType(for activity: WorkoutKitActivityRepresentation) -> HKWorkoutActivityType {
        switch activity {
        case .running: .running
        case .cycling: .cycling
        case .swimming: .swimming
        case .highIntensityIntervalTraining: .highIntensityIntervalTraining
        }
    }

    private func sessionLocation(for location: WorkoutKitLocationRepresentation) -> HKWorkoutSessionLocationType {
        switch location {
        case .indoor: .indoor
        case .outdoor: .outdoor
        case .unknown, .pool, .openWater: .unknown
        }
    }

    private func swimmingLocation(for location: WorkoutKitLocationRepresentation) -> HKWorkoutSwimmingLocationType {
        switch location {
        case .pool: .pool
        case .openWater: .openWater
        case .unknown, .indoor, .outdoor: .unknown
        }
    }

    private func intervalPurpose(for purpose: WorkoutKitStepRepresentation.Purpose) -> IntervalStep.Purpose {
        switch purpose {
        case .work: .work
        case .recovery: .recovery
        }
    }

    private func multisportActivity(_ activity: WorkoutKitMultisportActivity) -> SwimBikeRunWorkout.Activity {
        switch activity {
        case let .swimming(location): .swimming(swimmingLocation(for: location))
        case let .cycling(location): .cycling(sessionLocation(for: location))
        case let .running(location): .running(sessionLocation(for: location))
        }
    }

    /// The scheduling slot, as the fields WorkoutKit actually needs.
    ///
    /// `.calendar` and `.timeZone` used to be requested here, which stored a
    /// `Calendar` and `TimeZone` *inside* the `DateComponents`. `DateComponents`
    /// equality is structural over every field, so a value carrying a calendar
    /// could never compare equal to one WorkoutKit constructed — and equality is
    /// what `schedule` and `remove` use to confirm their own work. Every sync
    /// reported `scheduleFailed` immediately after scheduling.
    private func dateComponents(for date: Date) -> DateComponents {
        Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
    }

    /// Identity of a scheduled plan, compared field-wise rather than by
    /// `DateComponents ==`. Two components describing the same minute must match
    /// even if one carries fields the other leaves nil — which is exactly the
    /// asymmetry that arises when one side is ours and the other is the
    /// framework's.
    private func matches(_ scheduled: ScheduledWorkoutPlan, planID: UUID, slot: DateComponents) -> Bool {
        guard scheduled.plan.id == planID else { return false }
        let a = scheduled.date, b = slot
        return a.year == b.year && a.month == b.month && a.day == b.day
            && a.hour == b.hour && a.minute == b.minute
    }

    private func map(_ state: WorkoutScheduler.AuthorizationState) -> WorkoutSchedulingAuthorization {
        switch state {
        case .notDetermined: .notDetermined
        case .authorized: .authorized
        case .denied: .denied
        case .restricted: .restricted
        @unknown default: .unavailable
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

#endif

/// Production fallback for an OS/framework without WorkoutKit. It never
/// fabricates scheduling success; tests inject their own fake adapter.
public struct UnavailableWorkoutKitScheduler: WorkoutScheduling {
    public init() {}
    public var isSupported: Bool { false }
    public func authorizationState() async -> WorkoutSchedulingAuthorization { .unavailable }
    public func requestAuthorization() async -> WorkoutSchedulingAuthorization { .unavailable }
    public func schedule(_ request: WorkoutKitScheduleRequest) async throws {
        throw WorkoutKitSchedulingError.workoutKitUnavailable
    }
    public func remove(_ request: WorkoutKitScheduleRequest) async throws {
        throw WorkoutKitSchedulingError.workoutKitUnavailable
    }
    public func scheduledPlans() async throws -> [WorkoutKitScheduledPlan] {
        throw WorkoutKitSchedulingError.workoutKitUnavailable
    }
    public func removeAllEndurancePlans() async throws {
        throw WorkoutKitSchedulingError.workoutKitUnavailable
    }
}
