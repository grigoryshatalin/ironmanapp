import SwiftUI
import EnduranceDomain

/// The 36 weeks made understandable: grouped by phase, one row per week (brief
/// §10). Not a 270-day text file.
struct PlanView: View {
    @Environment(AppEnvironment.self) private var env
    private var store: WorkoutStore { env.store }

    @State private var filter = PlanFilter()

    var body: some View {
        List {
            if let plan = store.plan {
                if filter.isActive {
                    Section {
                        activeFilterSummary
                    }
                }
                ForEach(plan.phases) { phase in
                    let weeks = filteredWeeks(in: phase, plan: plan)
                    if !weeks.isEmpty {
                        Section {
                            ForEach(weeks, id: \.weekNumber) { week in
                                NavigationLink(value: week.weekNumber) {
                                    WeekRow(week: week, store: store)
                                }
                                .accessibilityIdentifier(A11y.Plan.week(week.weekNumber))
                            }
                        } header: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(phase.name)
                                Text(phase.objective)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textCase(nil)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityAddTraits(.isHeader)
                        }
                    }
                }
                if noMatches(plan: plan) {
                    Section {
                        EmptyStateView(systemImage: "line.3.horizontal.decrease.circle",
                                       title: "No matching sessions",
                                       message: "No week matches this filter. Clear it to see the whole plan.",
                                       actionTitle: "Clear filter",
                                       action: { filter = PlanFilter() })
                    }
                }
            } else {
                EmptyStateView(systemImage: "calendar",
                               title: "No plan loaded",
                               message: "Finish setup to see your plan.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Plan")
        .toolbar { filterMenu }
        .navigationDestination(for: Int.self) { WeekDetailView(week: $0) }
    }

    // MARK: - Filtering (§10)

    private var filterMenu: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Section("Sport") {
                    ForEach(PlanFilter.filterableSports, id: \.self) { sport in
                        Toggle(isOn: binding(for: sport)) {
                            Label(sport.localizedName, systemImage: Theme.symbol(for: sport))
                        }
                        .accessibilityIdentifier(A11y.Plan.filterOption(sport.rawValue))
                    }
                }
                Section("Status") {
                    ForEach(PlanFilter.Progress.allCases, id: \.self) { option in
                        Toggle(isOn: binding(for: option)) {
                            Text(verbatim: option.title)
                        }
                        .accessibilityIdentifier(A11y.Plan.filterOption(option.rawValue))
                    }
                }
                if filter.isActive {
                    Section {
                        Button(role: .destructive) { filter = PlanFilter() } label: {
                            Label("Clear filter", systemImage: "xmark.circle")
                        }
                        .accessibilityIdentifier(A11y.Plan.filterClear)
                    }
                }
            } label: {
                Label("Filter", systemImage: filter.isActive
                      ? "line.3.horizontal.decrease.circle.fill"
                      : "line.3.horizontal.decrease.circle")
            }
            .accessibilityIdentifier(A11y.Plan.filterMenu)
        }
    }

    private var activeFilterSummary: some View {
        HStack {
            Label(filter.summary, systemImage: "line.3.horizontal.decrease.circle.fill")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Clear") { filter = PlanFilter() }
                .font(.footnote)
        }
        .accessibilityElement(children: .combine)
    }

    private func binding(for sport: Sport) -> Binding<Bool> {
        Binding(
            get: { filter.sports.contains(sport) },
            set: { on in
                if on { filter.sports.insert(sport) } else { filter.sports.remove(sport) }
            })
    }

    private func binding(for option: PlanFilter.Progress) -> Binding<Bool> {
        Binding(
            get: { filter.progress.contains(option) },
            set: { on in
                if on { filter.progress.insert(option) } else { filter.progress.remove(option) }
            })
    }

    // MARK: - Data

    private func weeks(in phase: TrainingPhaseDefinition, plan: TrainingPlanDefinition) -> [TrainingWeekDefinition] {
        plan.weeks
            .filter { $0.weekNumber >= phase.startWeek && $0.weekNumber <= phase.endWeek }
            .sorted { $0.weekNumber < $1.weekNumber }
    }

    private func filteredWeeks(in phase: TrainingPhaseDefinition, plan: TrainingPlanDefinition) -> [TrainingWeekDefinition] {
        let all = weeks(in: phase, plan: plan)
        guard filter.isActive else { return all }
        return all.filter { week in
            filter.matches(store.workouts(inWeek: week.weekNumber))
        }
    }

    private func noMatches(plan: TrainingPlanDefinition) -> Bool {
        guard filter.isActive else { return false }
        return plan.phases.allSatisfy { filteredWeeks(in: $0, plan: plan).isEmpty }
    }
}

/// Which weeks the Plan screen shows. Kept as a value type so the filter state
/// is trivially testable and carries no view dependencies.
struct PlanFilter: Equatable {
    var sports: Set<Sport> = []
    var progress: Set<Progress> = []

    /// Brick and race are surfaced as sports because that is how an athlete
    /// thinks about them, even though a brick is stored as its own sport.
    static let filterableSports: [Sport] = [.swim, .bike, .run, .strength, .recovery, .brick, .race]

    enum Progress: String, CaseIterable, Hashable {
        case completed
        case missed
        case modified

        /// Already localized, so call sites use `Text(verbatim:)` semantics.
        var title: String {
            switch self {
            case .completed: return String(localized: "Completed")
            case .missed: return String(localized: "Missed")
            case .modified: return String(localized: "Modified")
            }
        }
    }

    var isActive: Bool { !sports.isEmpty || !progress.isEmpty }

    var summary: String {
        var parts: [String] = []
        if !sports.isEmpty {
            parts.append(sports.map(\.localizedName).sorted().joined(separator: ", "))
        }
        if !progress.isEmpty {
            parts.append(progress.map(\.title).sorted().joined(separator: ", "))
        }
        return parts.joined(separator: " · ")
    }

    /// A week matches when at least one of its sessions satisfies every active
    /// facet — so combining "Run" and "Completed" means "a completed run".
    func matches(_ workouts: [ScheduledWorkout]) -> Bool {
        guard isActive else { return true }
        return workouts.contains { workout in
            let sportOK = sports.isEmpty || sports.contains(workout.sport)
            let progressOK = progress.isEmpty || progress.contains { $0.matches(workout) }
            return sportOK && progressOK
        }
    }
}

extension PlanFilter.Progress {
    func matches(_ workout: ScheduledWorkout) -> Bool {
        switch self {
        case .completed:
            return workout.status == .completed || workout.status == .partiallyCompleted
        case .missed:
            return workout.status == .skipped
        case .modified:
            return !workout.modifications.isEmpty
        }
    }
}

struct WeekRow: View {
    let week: TrainingWeekDefinition
    let store: WorkoutStore

    private var scheduled: [ScheduledWorkout] { store.workouts(inWeek: week.weekNumber) }
    private var fmt: DisplayFormatter { DisplayFormatter(units: store.units) }

    private var dateRange: String {
        let dates = scheduled.map(\.scheduledDate)
        guard let lo = dates.min(), let hi = dates.max() else { return "" }
        return "\(lo.formatted(.dateTime.month().day())) – \(hi.formatted(.dateTime.month().day()))"
    }

    private var keyLong: String? {
        scheduled.first { $0.stressCategory == .long }?.title
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text("Week \(week.weekNumber)").font(.headline)
                loadTag
                Spacer(minLength: Theme.Space.s)
                Text(fmt.duration(minutes: week.plannedMinutes))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            if !dateRange.isEmpty {
                Text(dateRange).font(.caption).foregroundStyle(.secondary)
            }
            if let keyLong {
                Label(keyLong, systemImage: "star")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if isPast {
                let p = ProgressCalculator().weekProgress(week.weekNumber, in: store.allWorkouts)
                Text("\(p.completedSessionCount)/\(p.sessionCount) done")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var isPast: Bool {
        (scheduled.map(\.scheduledDate).max() ?? .distantFuture) < Date()
    }

    /// Load is text, never a bare color swatch, so it survives Differentiate
    /// Without Color and Increased Contrast.
    private var loadTag: some View {
        Text(week.load.localizedName)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(.quaternary, in: Capsule())
    }
}
