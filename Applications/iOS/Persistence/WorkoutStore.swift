import Foundation
import SwiftData
import Observation
import EnduranceDomain
import EnduranceTrainingPlans

/// The app's single gateway to persisted training state. Views never touch the
/// `ModelContext` directly (brief §18/§19). All mutations go through domain-typed
/// methods here, which keep the SwiftData payload, notifications, and the shared
/// snapshot consistent.
@MainActor
@Observable
final class WorkoutStore {
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }
    private let engine = ScheduleEngine()

    /// Cached settings-derived state, republished for the UI.
    private(set) var isConfigured = false
    private(set) var configuration: ScheduleConfiguration?
    private(set) var units: MeasurementSystem = .metric
    private(set) var notificationPreferences = NotificationPreferences()
    private(set) var plan: TrainingPlanDefinition?

    init(modelContainer: ModelContainer) {
        self.container = modelContainer
    }

    // MARK: - Load

    func load() throws {
        let settings = try settingsRow()
        isConfigured = settings?.onboarded ?? false
        configuration = settings?.configuration
        units = settings?.units ?? .metric
        notificationPreferences = settings?.preferences ?? NotificationPreferences()
        // The plan is read-only content — load & validate lazily.
        if isConfigured, plan == nil {
            plan = try? BundledPlans.load36Week()
        }
    }

    private func settingsRow() throws -> SDAppSettings? {
        try context.fetch(FetchDescriptor<SDAppSettings>()).first
    }

    // MARK: - Onboarding / bootstrap

    /// Complete first-run setup: validate the bundled plan, generate the schedule,
    /// and persist everything. Idempotent-ish: replaces any prior schedule.
    func completeOnboarding(
        configuration config: ScheduleConfiguration,
        units: MeasurementSystem,
        preferences: NotificationPreferences,
        raceName: String?,
        raceLocation: String?
    ) throws {
        let plan = try BundledPlans.load36Week() // throws on invalid/missing → surfaced by caller
        let schedule = try engine.generateSchedule(plan: plan, config: config)

        // Clear any existing schedule, then insert fresh.
        try deleteAllScheduled()
        for workout in schedule {
            context.insert(try SDScheduledWorkout(domain: workout))
        }

        let settings = try settingsRow() ?? SDAppSettings()
        settings.onboarded = true
        settings.planID = plan.id
        settings.units = units
        settings.configuration = config
        settings.preferences = preferences
        settings.raceName = raceName
        settings.raceLocation = raceLocation
        if settings.modelContext == nil { context.insert(settings) }

        try context.save()

        self.plan = plan
        self.configuration = config
        self.units = units
        self.notificationPreferences = preferences
        self.isConfigured = true
    }

    // MARK: - Queries

    var allWorkouts: [ScheduledWorkout] {
        (try? context.fetch(FetchDescriptor<SDScheduledWorkout>()).compactMap { try? $0.toDomain() }) ?? []
    }

    func workouts(onSameDayAs date: Date) -> [ScheduledWorkout] {
        let cal = configuration?.calendar ?? .current
        return allWorkouts
            .filter { cal.isDate($0.scheduledDate, inSameDayAs: date) }
            .sorted { $0.order < $1.order }
    }

    func workouts(inWeek week: Int) -> [ScheduledWorkout] {
        allWorkouts.filter { $0.weekNumber == week }.sorted { ($0.dayIndex, $0.order) < ($1.dayIndex, $1.order) }
    }

    func workout(id: UUID) -> ScheduledWorkout? {
        allWorkouts.first { $0.id == id }
    }

    /// The immutable template (structured steps, cues, fueling, gear, safety) a
    /// scheduled workout derives from. Looked up from the read-only plan by id.
    func template(for workout: ScheduledWorkout) -> WorkoutTemplate? {
        guard let templateID = workout.identity.templateID else { return nil }
        return plan?.weeks.lazy.flatMap { $0.days }.flatMap { $0.workouts }.first { $0.id == templateID }
    }

    /// Current training week for a date, derived from the schedule.
    func currentWeek(for date: Date) -> Int? {
        let cal = configuration?.calendar ?? .current
        return allWorkouts.first { cal.isDate($0.scheduledDate, inSameDayAs: date) }?.weekNumber
            ?? allWorkouts.filter { $0.scheduledDate <= date }.max(by: { $0.dayIndex < $1.dayIndex })?.weekNumber
    }

    // MARK: - Mutations (all persist + return the updated value)

    @discardableResult
    func complete(_ id: UUID, completion: WorkoutCompletion) throws -> ScheduledWorkout? {
        try mutate(id) {
            $0.status = completion.actualDurationMinutes != nil && $0.reducedDurationMinutes != nil ? .partiallyCompleted : .completed
            $0.completion = completion
        }
    }

    @discardableResult
    func markPartiallyComplete(_ id: UUID, completion: WorkoutCompletion) throws -> ScheduledWorkout? {
        try mutate(id) { $0.status = .partiallyCompleted; $0.completion = completion }
    }

    @discardableResult
    func skip(_ id: UUID, reason: String?) throws -> ScheduledWorkout? {
        try mutate(id) { w in
            w.status = .skipped
            w.modifications.append(PlanModification(type: .skip, createdAt: Date(), reason: reason))
        }
    }

    @discardableResult
    func reschedule(_ id: UUID, to newDate: Date) throws -> ScheduledWorkout? {
        try mutate(id) { [weak self] w in
            let old = w.scheduledDate
            let cal = self?.configuration?.calendar ?? .current
            let day = cal.startOfDay(for: newDate)
            w.scheduledDate = day
            w.plannedStart = self?.resolveStart(on: day, like: w.plannedStart) ?? w.plannedStart
            w.status = .rescheduled
            w.modifications.append(PlanModification(type: .reschedule, createdAt: Date(), oldDate: old, newDate: day))
        }
    }

    @discardableResult
    func reduce(_ id: UUID, toMinutes minutes: Int) throws -> ScheduledWorkout? {
        try mutate(id) { w in
            let old = w.effectivePlannedMinutes
            w.reducedDurationMinutes = minutes
            w.modifications.append(PlanModification(type: .shorten, createdAt: Date(), oldDurationMinutes: old, newDurationMinutes: minutes))
        }
    }

    @discardableResult
    func replaceWithRecovery(_ id: UUID) throws -> ScheduledWorkout? {
        try mutate(id) { w in
            w.status = .replaced
            w.modifications.append(PlanModification(type: .replaceWithRecovery, createdAt: Date(), reason: "Replaced with recovery"))
        }
    }

    @discardableResult
    func addNote(_ id: UUID, note: String) throws -> ScheduledWorkout? {
        try mutate(id) { w in
            var c = w.completion ?? WorkoutCompletion(completedAt: Date(), source: .manual)
            c.notes = note
            w.completion = c
            w.modifications.append(PlanModification(type: .note, createdAt: Date(), reason: "Note added"))
        }
    }

    /// Undo the most recent modification and restore prior status/dates.
    @discardableResult
    func undoLast(_ id: UUID) throws -> ScheduledWorkout? {
        try mutate(id) { w in
            guard let last = w.modifications.popLast() else { return }
            switch last.type {
            case .reschedule:
                if let old = last.oldDate { w.scheduledDate = old }
                w.status = .planned
            case .shorten:
                w.reducedDurationMinutes = nil
            case .skip, .replaceWithRecovery:
                w.status = .planned
            default:
                break
            }
        }
    }

    /// Recalculate FUTURE planned dates when the plan anchor changes; completed
    /// and past sessions keep their historical dates (brief §12/§17).
    func changeAnchor(to newConfig: ScheduleConfiguration, now: Date = Date()) throws {
        guard let plan else { return }
        let startDay = try engine.startDay(plan: plan, config: newConfig)
        let cal = newConfig.calendar
        let records = try context.fetch(FetchDescriptor<SDScheduledWorkout>())
        for record in records {
            var w = try record.toDomain()
            let isPastOrDone = w.status.countsAsDone || w.scheduledDate < cal.startOfDay(for: now)
            guard !isPastOrDone else { continue }
            let newDay = engine.date(forDayIndex: w.dayIndex, startDay: startDay, config: newConfig)
            w.scheduledDate = newDay
            w.plannedStart = resolveStart(on: newDay, like: w.plannedStart)
            try record.update(w)
        }
        let settings = try settingsRow() ?? SDAppSettings()
        settings.configuration = newConfig
        if settings.modelContext == nil { context.insert(settings) }
        try context.save()
        self.configuration = newConfig
    }

    /// Re-apply the athlete's preferred long-ride / long-run / rest days.
    ///
    /// Regenerates the schedule through `ScheduleEngine` — the same path
    /// onboarding uses — then adopts only the *future, unfinished* dates.
    /// Scheduled ids are derived from the plan's canonical day, so they are
    /// unchanged by the new layout and completion history matches straight
    /// across (§28.2).
    func applyPreferredDays(_ newConfig: ScheduleConfiguration, now: Date = Date()) throws {
        guard let plan else { return }
        let regenerated = try engine.generateSchedule(plan: plan, config: newConfig)
        let byID = Dictionary(uniqueKeysWithValues: regenerated.map { ($0.id, $0) })
        let cal = newConfig.calendar
        let today = cal.startOfDay(for: now)

        for record in try context.fetch(FetchDescriptor<SDScheduledWorkout>()) {
            var w = try record.toDomain()
            // Never move something already done, or already in the past.
            guard !w.status.countsAsDone, w.scheduledDate >= today else { continue }
            guard let fresh = byID[w.id] else { continue }
            w.scheduledDate = fresh.scheduledDate
            w.plannedStart = fresh.plannedStart
            w.dayIndex = fresh.dayIndex
            w.weekdayOffset = fresh.weekdayOffset
            try record.update(w)
        }

        let settings = try settingsRow() ?? SDAppSettings()
        settings.configuration = newConfig
        if settings.modelContext == nil { context.insert(settings) }
        try context.save()
        self.configuration = newConfig
    }

    func updatePreferences(_ prefs: NotificationPreferences) throws {
        let settings = try settingsRow() ?? SDAppSettings()
        settings.preferences = prefs
        if settings.modelContext == nil { context.insert(settings) }
        try context.save()
        notificationPreferences = prefs
    }

    func updateUnits(_ u: MeasurementSystem) throws {
        let settings = try settingsRow() ?? SDAppSettings()
        settings.units = u
        if settings.modelContext == nil { context.insert(settings) }
        try context.save()
        units = u
    }

    // MARK: - Data management (destructive; callers confirm first)

    /// Clear completions/statuses but keep the schedule (brief §12).
    func resetCompletionHistory() throws {
        let records = try context.fetch(FetchDescriptor<SDScheduledWorkout>())
        for record in records {
            var w = try record.toDomain()
            w.status = .planned
            w.completion = nil
            w.reducedDurationMinutes = nil
            w.modifications = []
            try record.update(w)
        }
        try context.save()
    }

    /// Delete everything and return to onboarding.
    func deleteAllData() throws {
        try context.delete(model: SDScheduledWorkout.self)
        try context.delete(model: SDAppSettings.self)
        try context.save()
        isConfigured = false
        configuration = nil
        plan = nil
    }

    /// Build a portable export of current state.
    func makeExport() -> TrainingHistoryExport? {
        guard let config = configuration else { return nil }
        let settings = try? settingsRow()
        return TrainingHistoryExport(
            exportedAt: Date(),
            planID: settings?.planID,
            scheduleConfiguration: config,
            notificationPreferences: notificationPreferences,
            units: units,
            scheduledWorkouts: allWorkouts)
    }

    // MARK: - Snapshot for widgets/watch

    func todaySnapshot(now: Date = Date()) -> SharedTodaySnapshot {
        let today = workouts(onSameDayAs: now)
        let calc = ProgressCalculator()
        let week = currentWeek(for: now) ?? 1
        let wp = calc.weekProgress(week, in: allWorkouts)
        let next = today.first { $0.status == .planned && $0.plannedStart >= now } ?? today.first { $0.status == .planned }
        let phaseName = plan?.phase(forWeek: week)?.name ?? ""
        return SharedTodaySnapshot(
            generatedAt: now,
            trainingDayID: nil,
            weekNumber: week,
            totalWeeks: plan?.durationWeeks ?? 36,
            phaseName: phaseName,
            nextWorkoutID: next?.id,
            nextWorkoutTitle: next?.title,
            nextWorkoutSport: next?.sport,
            nextWorkoutStart: next?.plannedStart,
            plannedMinutes: wp.plannedMinutes,
            completedMinutes: wp.completedMinutes,
            sessionCount: today.filter { !$0.isOptional }.count,
            completedSessionCount: today.filter { $0.status.countsAsDone }.count,
            isRecoveryDay: today.allSatisfy { $0.stressCategory == .recovery } && !today.isEmpty)
    }

    // MARK: - Helpers

    private func mutate(_ id: UUID, _ change: (inout ScheduledWorkout) -> Void) throws -> ScheduledWorkout? {
        let descriptor = FetchDescriptor<SDScheduledWorkout>(predicate: #Predicate { $0.id == id })
        guard let record = try context.fetch(descriptor).first else { return nil }
        var domain = try record.toDomain()
        change(&domain)
        try record.update(domain)
        try context.save()
        return domain
    }

    /// Resolve a start instant on `day` reusing the time-of-day of `reference`
    /// (so a moved workout keeps its clock time), DST-safe.
    private func resolveStart(on day: Date, like reference: Date) -> Date {
        let cal = configuration?.calendar ?? .current
        let comps = cal.dateComponents([.hour, .minute], from: reference)
        return cal.date(bySettingHour: comps.hour ?? 7, minute: comps.minute ?? 0, second: 0, of: day) ?? day
    }

    private func deleteAllScheduled() throws {
        try context.delete(model: SDScheduledWorkout.self)
    }
}
