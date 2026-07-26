import SwiftUI
import EnduranceDomain

/// The center of the app: answers "what should I do today?" at a glance (brief
/// §8). Calm status, chronological sessions, progressive disclosure.
struct TodayView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var now = Date()
    @State private var completing: ScheduledWorkout?
    @State private var rescheduling: ScheduledWorkout?
    /// Bumped after a successful mutation, purely to drive haptics.
    @State private var completionTick = 0
    @State private var rescheduleTick = 0

    private var store: WorkoutStore { env.store }
    private var fmt: DisplayFormatter { DisplayFormatter(units: store.units) }
    private var todays: [ScheduledWorkout] { store.workouts(onSameDayAs: now) }
    private var week: Int { store.currentWeek(for: now) ?? 1 }
    private var phaseName: String { store.plan?.phase(forWeek: week)?.name ?? "" }

    var body: some View {
        List {
            headerSection

            if todays.isEmpty {
                Section {
                    EmptyStateView(systemImage: "bed.double",
                                   title: "Nothing scheduled today",
                                   message: "Rest is part of the plan. Your next session is below.")
                        .accessibilityIdentifier(A11y.Today.empty)
                }
            } else {
                Section {
                    ForEach(Array(todays.enumerated()), id: \.element.id) { index, workout in
                        NavigationLink(value: workout.id) {
                            TodayWorkoutRow(workout: workout, fmt: fmt, index: index)
                        }
                        .swipeActions(edge: .trailing) {
                            if workout.status == .planned {
                                Button { completing = workout } label: {
                                    Label("Complete", systemImage: "checkmark")
                                }
                                .tint(.green)
                                .accessibilityIdentifier(A11y.Today.completeAction)
                            }
                        }
                        .swipeActions(edge: .leading) {
                            Button { rescheduling = workout } label: {
                                Label("Reschedule", systemImage: "arrow.right")
                            }
                            .tint(.orange)
                            .accessibilityIdentifier(A11y.Today.rescheduleAction)
                        }
                        .contextMenu { menu(for: workout) }
                    }
                } header: {
                    Text("Today’s sessions")
                }
            }

            // A quiet day leaves space; fill it with the one genuinely useful
            // thing rather than decoration (§13).
            upNextSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Today")
        .navigationDestination(for: UUID.self) { id in
            if let w = store.workout(id: id) { WorkoutDetailView(workoutID: w.id) }
        }
        .navigationDestination(isPresented: pendingBinding) {
            if let id = env.pendingWorkoutID, let w = store.workout(id: id) { WorkoutDetailView(workoutID: w.id) }
        }
        .sheet(item: $completing) { w in
            CompletionSheet(workout: w, units: store.units) { completion in await complete(w, completion) }
        }
        .sheet(item: $rescheduling) { w in
            RescheduleSheet(workout: w, store: store) { date in await reschedule(w, to: date) }
        }
        .haptic(.completed, trigger: completionTick)
        .haptic(.rescheduled, trigger: rescheduleTick)
        .animation(reduceMotion ? nil : .default, value: todays.map(\.status))
        .refreshable { now = Date() }
        .task { now = Date() }
    }

    // MARK: - Sections

    /// Date, week/phase, weekly progress and the day's status live in ONE
    /// grouped section. They were three separate rounded cards, which made the
    /// screen read as a stack of floating panels rather than a native grouped
    /// list (§9). The status now sits in the section footer, where iOS
    /// conventionally puts a summary line.
    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text(dateText)
                    .font(.title2)
                    .accessibilityIdentifier(A11y.Today.date)
                Text(weekPhaseText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier(A11y.Today.weekPhase)
                // At accessibility text sizes this header alone filled the whole
                // screen and pushed today's sessions off it — which defeats the
                // one question this screen exists to answer (§8). Weekly
                // progress is secondary and lives on the Progress tab, so it
                // yields here rather than truncating anything.
                if !dynamicTypeSize.isAccessibilitySize {
                    WeekProgressBar(week: week, store: store)
                        .padding(.top, Theme.Space.xs)
                        .accessibilityIdentifier(A11y.Today.weekProgress)
                }
            }
            .padding(.vertical, Theme.Space.xs)
        } footer: {
            Label(statusText, systemImage: statusSymbol)
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.top, Theme.Space.xs)
                .accessibilityIdentifier(A11y.Today.status)
        }
    }

    /// A shorter date at accessibility sizes: "Sat, Jul 25" instead of wrapping
    /// "Saturday, July 25" onto three lines.
    private var dateText: String {
        dynamicTypeSize.isAccessibilitySize
            ? now.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
            : DisplayFormatter.longDate(now)
    }

    private var weekPhaseText: String {
        let total = store.plan?.durationWeeks ?? 36
        guard !phaseName.isEmpty else { return String(localized: "Week \(week) of \(total)") }
        return String(localized: "Week \(week) of \(total) · \(phaseName)")
    }

    private var statusText: String {
        if todays.isEmpty { return String(localized: "Recovery day — nothing scheduled.") }
        let remaining = todays.filter { $0.status == .planned }.count
        if remaining == 0 { return String(localized: "All sessions complete. Well done.") }
        if todays.allSatisfy({ $0.stressCategory == .recovery }) { return String(localized: "Recovery day — keep it easy.") }
        if week == (store.plan?.durationWeeks ?? 36) { return String(localized: "Race week.") }
        return remaining == 1
            ? String(localized: "One session remains.")
            : String(localized: "Ready for today — \(remaining) sessions.")
    }

    private var statusSymbol: String {
        todays.isEmpty || todays.allSatisfy { $0.stressCategory == .recovery } ? "bed.double" : "figure.mixed.cardio"
    }

    /// Shown only when today is genuinely quiet — empty, all recovery, or all
    /// done — so a normal training day is never padded out.
    @ViewBuilder private var upNextSection: some View {
        if isQuietDay, let next = nextUpcoming {
            Section {
                NavigationLink(value: next.id) {
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        Text(next.plannedStart, format: .dateTime.weekday(.wide).month().day())
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        HStack(alignment: .top, spacing: Theme.Space.m) {
                            SportBadge(sport: next.sport)
                            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                                Text(next.title).font(.headline)
                                MetricLine(parts: [
                                    fmt.duration(minutes: next.effectivePlannedMinutes),
                                    fmt.distance(next.plannedDistanceMeters, sport: next.sport) ?? "",
                                    fmt.intensity(next.intensity),
                                ])
                            }
                        }
                    }
                    .padding(.vertical, Theme.Space.xs)
                    .accessibilityElement(children: .combine)
                }
                .accessibilityIdentifier(A11y.Today.upNext)
            } header: {
                Text("Up next")
            }
        }
    }

    private var isQuietDay: Bool {
        todays.isEmpty
            || todays.allSatisfy { $0.stressCategory == .recovery }
            || todays.allSatisfy { $0.status.countsAsDone }
    }

    private var nextUpcoming: ScheduledWorkout? {
        let cal = store.configuration?.calendar ?? .current
        let endOfToday = cal.startOfDay(for: now).addingTimeInterval(24 * 60 * 60)
        return store.allWorkouts
            .filter { $0.plannedStart >= endOfToday && $0.status == .planned }
            .min { $0.plannedStart < $1.plannedStart }
    }

    // MARK: - Actions

    @ViewBuilder private func menu(for w: ScheduledWorkout) -> some View {
        if w.status == .planned {
            Button { completing = w } label: { Label("Mark complete", systemImage: "checkmark.circle") }
                .accessibilityIdentifier(A11y.Today.completeAction)
            Button { rescheduling = w } label: { Label("Reschedule", systemImage: "arrow.right.circle") }
                .accessibilityIdentifier(A11y.Today.rescheduleAction)
            Button { Task { await run { try store.replaceWithRecovery(w.id) } } } label: {
                Label("Replace with recovery", systemImage: "bed.double")
            }
            .accessibilityIdentifier(A11y.Today.replaceAction)
            Button(role: .destructive) { Task { await run { try store.skip(w.id, reason: nil) } } } label: {
                Label("Skip", systemImage: "minus.circle")
            }
            .accessibilityIdentifier(A11y.Today.skipAction)
        } else {
            Button { Task { await run { try store.undoLast(w.id) } } } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
            }
            .accessibilityIdentifier(A11y.Today.undoAction)
        }
    }

    private func complete(_ w: ScheduledWorkout, _ completion: WorkoutCompletion) async {
        await run { try store.complete(w.id, completion: completion) }
        env.notifications.cancel(for: w.id) // completing cancels its reminders (§8)
        completionTick += 1
    }

    private func reschedule(_ w: ScheduledWorkout, to date: Date) async {
        await run { try store.reschedule(w.id, to: date) }
        rescheduleTick += 1
    }

    /// Run a mutation, then refresh notifications + snapshot. Surfaces failures
    /// as a calm alert rather than crashing.
    private func run(_ work: () throws -> Void) async {
        do {
            try work()
            await env.refreshSideEffects()
        } catch {
            AppLog.app.error("Action failed: \(error)")
            env.alert = .dataError
        }
    }

    private var pendingBinding: Binding<Bool> {
        Binding(get: { env.pendingWorkoutID != nil },
                set: { if !$0 { env.pendingWorkoutID = nil } })
    }
}
