import SwiftUI
import EnduranceDomain

/// The center of the app: answers "what should I do today?" at a glance (brief
/// §8). Calm status, chronological sessions, progressive disclosure.
struct TodayView: View {
    @Environment(AppEnvironment.self) private var env

    @State private var now = Date()
    @State private var completing: ScheduledWorkout?
    @State private var rescheduling: ScheduledWorkout?

    private var store: WorkoutStore { env.store }
    private var fmt: DisplayFormatter { DisplayFormatter(units: store.units) }
    private var todays: [ScheduledWorkout] { store.workouts(onSameDayAs: now) }
    private var week: Int { store.currentWeek(for: now) ?? 1 }
    private var phaseName: String { store.plan?.phase(forWeek: week)?.name ?? "" }

    var body: some View {
        List {
            headerSection
            statusSection

            if todays.isEmpty {
                Section {
                    EmptyStateView(systemImage: "checkmark.circle",
                                   title: "Nothing scheduled today",
                                   message: "Enjoy the rest, or browse the week in Plan.")
                }
            } else {
                Section {
                    ForEach(todays) { workout in
                        NavigationLink(value: workout.id) {
                            TodayWorkoutRow(workout: workout, fmt: fmt)
                        }
                        .swipeActions(edge: .trailing) {
                            if workout.status == .planned {
                                Button { completing = workout } label: { Label("Complete", systemImage: "checkmark") }
                                    .tint(.green)
                            }
                        }
                        .swipeActions(edge: .leading) {
                            Button { rescheduling = workout } label: { Label("Reschedule", systemImage: "arrow.right") }
                                .tint(.orange)
                        }
                        .contextMenu { menu(for: workout) }
                    }
                } header: {
                    Text("Today’s sessions")
                }
            }
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
            CompletionSheet(workout: w) { completion in await complete(w, completion) }
        }
        .sheet(item: $rescheduling) { w in
            RescheduleSheet(workout: w, store: store) { date in await reschedule(w, to: date) }
        }
        .refreshable { now = Date() }
        .task { now = Date() }
    }

    // MARK: - Sections

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text(DisplayFormatter.longDate(now))
                    .font(.title2).bold()
                HStack(spacing: Theme.Space.s) {
                    Text("Week \(week) of \(store.plan?.durationWeeks ?? 36)")
                    if !phaseName.isEmpty {
                        Text("·"); Text(phaseName)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                WeekProgressBar(week: week, store: store)
                    .padding(.top, Theme.Space.xs)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var statusSection: some View {
        Section {
            Label(statusText, systemImage: statusSymbol)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var statusText: String {
        if todays.isEmpty { return "Recovery day — nothing scheduled." }
        let remaining = todays.filter { $0.status == .planned }.count
        if remaining == 0 { return "All sessions complete. Well done." }
        if todays.allSatisfy({ $0.stressCategory == .recovery }) { return "Recovery day — keep it easy." }
        if week == (store.plan?.durationWeeks ?? 36) { return "Race week." }
        return remaining == 1 ? "One session remains." : "Ready for today — \(remaining) sessions."
    }
    private var statusSymbol: String {
        todays.isEmpty || todays.allSatisfy { $0.stressCategory == .recovery } ? "bed.double" : "figure.mixed.cardio"
    }

    // MARK: - Actions

    @ViewBuilder private func menu(for w: ScheduledWorkout) -> some View {
        if w.status == .planned {
            Button { completing = w } label: { Label("Mark complete", systemImage: "checkmark.circle") }
            Button { rescheduling = w } label: { Label("Reschedule", systemImage: "arrow.right.circle") }
            Button { Task { await run { try store.replaceWithRecovery(w.id) } } } label: { Label("Replace with recovery", systemImage: "bed.double") }
            Button(role: .destructive) { Task { await run { try store.skip(w.id, reason: nil) } } } label: { Label("Skip", systemImage: "minus.circle") }
        } else {
            Button { Task { await run { try store.undoLast(w.id) } } } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
        }
    }

    private func complete(_ w: ScheduledWorkout, _ completion: WorkoutCompletion) async {
        await run {
            try store.complete(w.id, completion: completion)
        }
        env.notifications.cancel(for: w.id) // completing cancels its reminders (§8)
    }

    private func reschedule(_ w: ScheduledWorkout, to date: Date) async {
        await run { try store.reschedule(w.id, to: date) }
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
