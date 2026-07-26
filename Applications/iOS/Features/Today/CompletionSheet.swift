import SwiftUI
import EnduranceDomain

/// Log a completed session. Everything is optional — tapping Save with nothing
/// filled records "done", which is enough (brief §8).
struct CompletionSheet: View {
    let workout: ScheduledWorkout
    let onSave: (WorkoutCompletion) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var minutes: Double
    @State private var logDistance = false
    @State private var distanceValue: Double = 0
    @State private var rpe = 5.0
    @State private var fatigue = 3.0
    @State private var soreness = 3.0
    @State private var notes = ""

    init(workout: ScheduledWorkout, onSave: @escaping (WorkoutCompletion) async -> Void) {
        self.workout = workout
        self.onSave = onSave
        _minutes = State(initialValue: Double(workout.effectivePlannedMinutes))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Actual duration") {
                    Stepper(value: $minutes, in: 0...600, step: 5) {
                        Text("\(Int(minutes)) min")
                    }
                }
                Section("Distance") {
                    Toggle("Log distance", isOn: $logDistance)
                    if logDistance {
                        HStack {
                            TextField("Distance", value: $distanceValue, format: .number)
                                .keyboardType(.decimalPad)
                            Text(UnitFormatter().displayUnit(for: workout.sport, system: .metric).symbol)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Section("How did it feel?") {
                    ratingRow("Perceived exertion", value: $rpe, range: 1...10)
                    ratingRow("Fatigue", value: $fatigue, range: 1...5)
                    ratingRow("Soreness", value: $soreness, range: 1...5)
                }
                Section("Notes") {
                    TextField("Optional", text: $notes, axis: .vertical).lineLimit(1...4)
                }
            }
            .navigationTitle("Complete session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                }
            }
        }
    }

    private func ratingRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading) {
            HStack { Text(title); Spacer(); Text("\(Int(value.wrappedValue))").monospacedDigit().foregroundStyle(.secondary) }
            Slider(value: value, in: range, step: 1)
                .accessibilityValue("\(Int(value.wrappedValue)) of \(Int(range.upperBound))")
        }
    }

    private func save() async {
        let completion = WorkoutCompletion(
            completedAt: Date(),
            actualDurationMinutes: Int(minutes),
            actualDistanceMeters: logDistance ? UnitFormatter().meters(from: distanceValue, in: UnitFormatter().displayUnit(for: workout.sport, system: .metric)) : nil,
            perceivedExertion: Int(rpe),
            fatigue: Int(fatigue),
            soreness: Int(soreness),
            notes: notes.isEmpty ? nil : notes,
            source: .manual)
        await onSave(completion)
        dismiss()
    }
}
