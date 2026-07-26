import SwiftUI
import EnduranceDomain

/// Log a completed session. Everything is optional — tapping Save with nothing
/// filled records "done", which is enough (brief §8).
struct CompletionSheet: View {
    let workout: ScheduledWorkout
    /// The athlete's chosen units, so the distance field is entered and stored
    /// in the units actually on screen.
    var units: MeasurementSystem = .metric
    let onSave: (WorkoutCompletion) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var minutes: Double
    @State private var logDistance = false
    @State private var distanceValue: Double = 0
    @State private var rpe = 5.0
    @State private var fatigue = 3.0
    @State private var soreness = 3.0
    @State private var notes = ""

    init(
        workout: ScheduledWorkout,
        units: MeasurementSystem = .metric,
        onSave: @escaping (WorkoutCompletion) async -> Void
    ) {
        self.workout = workout
        self.units = units
        self.onSave = onSave
        _minutes = State(initialValue: Double(workout.effectivePlannedMinutes))
    }

    private var distanceUnit: UnitLength {
        UnitFormatter().displayUnit(for: workout.sport, system: units)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Actual duration") {
                    Stepper(value: $minutes, in: 0...600, step: 5) {
                        Text("\(Int(minutes)) min")
                            .monospacedDigit()
                            .accessibilityIdentifier(A11y.Completion.minutesValue)
                    }
                    .accessibilityIdentifier(A11y.Completion.minutes)
                    .accessibilityValue(Text("\(Int(minutes)) minutes"))
                }
                Section("Distance") {
                    Toggle("Log distance", isOn: $logDistance)
                        .accessibilityIdentifier(A11y.Completion.logDistance)
                    if logDistance {
                        HStack {
                            TextField("Distance", value: $distanceValue, format: .number)
                                .keyboardType(.decimalPad)
                                .accessibilityIdentifier(A11y.Completion.distance)
                            Text(distanceUnit.symbol)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Section("How did it feel?") {
                    ratingRow("Perceived exertion", value: $rpe, range: 1...10)
                        .accessibilityIdentifier(A11y.Completion.rpe)
                    ratingRow("Fatigue", value: $fatigue, range: 1...5)
                    ratingRow("Soreness", value: $soreness, range: 1...5)
                }
                Section("Notes") {
                    TextField("Optional", text: $notes, axis: .vertical)
                        .lineLimit(1...4)
                        .accessibilityIdentifier(A11y.Completion.notes)
                }
            }
            .navigationTitle("Complete session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier(A11y.Completion.cancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .accessibilityIdentifier(A11y.Completion.save)
                }
            }
        }
    }

    private func ratingRow(_ title: LocalizedStringKey, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int(value.wrappedValue))")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: 1)
                .accessibilityValue("\(Int(value.wrappedValue)) of \(Int(range.upperBound))")
        }
        .accessibilityElement(children: .contain)
    }

    private func save() async {
        let completion = WorkoutCompletion(
            completedAt: Date(),
            actualDurationMinutes: Int(minutes),
            actualDistanceMeters: logDistance
                ? UnitFormatter().meters(from: distanceValue, in: distanceUnit)
                : nil,
            perceivedExertion: Int(rpe),
            fatigue: Int(fatigue),
            soreness: Int(soreness),
            notes: notes.isEmpty ? nil : notes,
            source: .manual)
        await onSave(completion)
        dismiss()
    }
}
