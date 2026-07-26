import SwiftUI
import EnduranceDomain

/// Move a session to another day, surfacing calm, advisory safety warnings
/// (never blocking) from the tested `AdaptationAdvisor` (brief §14).
struct RescheduleSheet: View {
    let workout: ScheduledWorkout
    let store: WorkoutStore
    let onConfirm: (Date) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var newDate: Date

    private let advisor = AdaptationAdvisor()

    init(workout: ScheduledWorkout, store: WorkoutStore, onConfirm: @escaping (Date) async -> Void) {
        self.workout = workout
        self.store = store
        self.onConfirm = onConfirm
        _newDate = State(initialValue: workout.scheduledDate)
    }

    private var calendar: Calendar { store.configuration?.calendar ?? .current }

    private var warnings: [AdaptationAdvisor.Warning] {
        advisor.warningsForMoving(workout, to: newDate, within: store.allWorkouts, calendar: calendar) { date in
            store.allWorkouts.first { calendar.isDate($0.scheduledDate, inSameDayAs: date) }
                .flatMap { w in store.plan?.weeks.first { $0.weekNumber == w.weekNumber }?.load }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("New day", selection: $newDate, displayedComponents: .date)
                        .accessibilityIdentifier(A11y.Reschedule.datePicker)
                }
                if warnings.isEmpty {
                    Section {
                        // Symbol + wording carry the meaning; the tint is only a
                        // reinforcement (Differentiate Without Color).
                        Label("No conflicts on that day.", systemImage: "checkmark.circle")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityIdentifier(A11y.Reschedule.warnings)
                } else {
                    Section("Worth considering") {
                        ForEach(warnings) { w in
                            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                                Label(w.message, systemImage: "exclamationmark.triangle")
                                    .font(.callout)
                                Text(w.whatStaysUnchanged)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .accessibilityIdentifier(A11y.Reschedule.warnings)
                }
                Section {
                    Text("Moving a session never stacks it onto a hard day automatically. Consistency matters more than any single workout.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Reschedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier(A11y.Reschedule.cancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Move") { Task { await onConfirm(newDate); dismiss() } }
                        .accessibilityIdentifier(A11y.Reschedule.confirm)
                }
            }
        }
    }
}
