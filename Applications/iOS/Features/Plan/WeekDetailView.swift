import SwiftUI
import EnduranceDomain

/// One week's objective, distribution, and day-by-day sessions (brief §10).
struct WeekDetailView: View {
    let week: Int
    @Environment(AppEnvironment.self) private var env
    private var store: WorkoutStore { env.store }
    private var fmt: DisplayFormatter { DisplayFormatter(units: store.units) }

    private var weekDef: TrainingWeekDefinition? {
        store.plan?.weeks.first { $0.weekNumber == week }
    }
    private var scheduled: [ScheduledWorkout] { store.workouts(inWeek: week) }

    var body: some View {
        List {
            if let def = weekDef {
                Section {
                    Text(def.objective).font(.body)
                    LabeledContent("Planned time", value: fmt.duration(minutes: def.plannedMinutes))
                    if def.load == .recovery {
                        // Wording and symbol carry the meaning; no color-only cue.
                        Label("Recovery week — keep it genuinely easy.", systemImage: "bed.double")
                            .foregroundStyle(.secondary)
                    }
                    if let note = def.coachNote {
                        Label(note, systemImage: "text.bubble").font(.callout).foregroundStyle(.secondary)
                    }
                }
            }

            let byDay = Dictionary(grouping: scheduled, by: \.dayIndex).sorted { $0.key < $1.key }
            ForEach(byDay, id: \.key) { _, workouts in
                Section {
                    ForEach(Array(workouts.sorted { $0.order < $1.order }.enumerated()), id: \.element.id) { index, w in
                        NavigationLink(value: w.id) {
                            TodayWorkoutRow(workout: w, fmt: fmt, index: index)
                        }
                    }
                } header: {
                    Text(workouts.first?.scheduledDate ?? Date(), format: .dateTime.weekday(.wide).month().day())
                        .accessibilityAddTraits(.isHeader)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Week \(week)")
        .navigationDestination(for: UUID.self) { id in WorkoutDetailView(workoutID: id) }
    }
}
