import SwiftUI
import EnduranceDomain

/// The 36 weeks made understandable: grouped by phase, one row per week (brief
/// §10). Not a 270-day text file.
struct PlanView: View {
    @Environment(AppEnvironment.self) private var env
    private var store: WorkoutStore { env.store }

    var body: some View {
        List {
            if let plan = store.plan {
                ForEach(plan.phases) { phase in
                    Section {
                        ForEach(weeks(in: phase, plan: plan), id: \.weekNumber) { week in
                            NavigationLink(value: week.weekNumber) {
                                WeekRow(week: week, store: store)
                            }
                        }
                    } header: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(phase.name)
                            Text(phase.objective).font(.caption).foregroundStyle(.secondary).textCase(nil)
                        }
                    }
                }
            } else {
                EmptyStateView(systemImage: "calendar", title: "No plan loaded", message: "Finish setup to see your plan.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Plan")
        .navigationDestination(for: Int.self) { WeekDetailView(week: $0) }
    }

    private func weeks(in phase: TrainingPhaseDefinition, plan: TrainingPlanDefinition) -> [TrainingWeekDefinition] {
        plan.weeks.filter { $0.weekNumber >= phase.startWeek && $0.weekNumber <= phase.endWeek }
            .sorted { $0.weekNumber < $1.weekNumber }
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
            HStack {
                Text("Week \(week.weekNumber)").font(.headline)
                loadTag
                Spacer()
                Text(fmt.duration(minutes: week.plannedMinutes)).font(.subheadline).foregroundStyle(.secondary)
            }
            if !dateRange.isEmpty {
                Text(dateRange).font(.caption).foregroundStyle(.secondary)
            }
            if let keyLong { Label(keyLong, systemImage: "star").font(.caption).foregroundStyle(.secondary) }
            if isPast {
                let p = ProgressCalculator().weekProgress(week.weekNumber, in: store.allWorkouts)
                Text("\(p.completedSessionCount)/\(p.sessionCount) done").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var isPast: Bool {
        (store.workouts(inWeek: week.weekNumber).map(\.scheduledDate).max() ?? .distantFuture) < Date()
    }

    private var loadTag: some View {
        Text(week.load.rawValue.capitalized)
            .font(.caption2)
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(week.load == .recovery ? Color.purple.opacity(0.2) : Color.secondary.opacity(0.15), in: Capsule())
            .foregroundStyle(week.load == .recovery ? .purple : .secondary)
    }
}
