import SwiftUI
import EnduranceDomain

/// Full workout detail with progressive disclosure (brief §9). Structured
/// warm-up / main set / cool-down rather than a wall of text.
struct WorkoutDetailView: View {
    let workoutID: UUID
    @Environment(AppEnvironment.self) private var env

    private var store: WorkoutStore { env.store }
    private var workout: ScheduledWorkout? { store.workout(id: workoutID) }
    private var template: WorkoutTemplate? { workout.flatMap { store.template(for: $0) } }
    private var fmt: DisplayFormatter { DisplayFormatter(units: store.units) }

    @State private var completing = false

    var body: some View {
        if let workout {
            List {
                headerSection(workout)
                purposeSection(workout)
                if let t = template {
                    stepSection("Warm-up", "flame", t.warmup)
                    stepSection("Main set", "bolt", t.mainSet)
                    stepSection("Cool-down", "wind", t.cooldown)
                    cuesSection(t)
                    fuelingSection(t)
                    gearSafetySection(t)
                }
                statusSection(workout)
                historySection(workout)
            }
            .listStyle(.insetGrouped)
            .navigationTitle(workout.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if workout.status == .planned {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Complete") { completing = true }
                    }
                }
            }
            .sheet(isPresented: $completing) {
                CompletionSheet(workout: workout) { completion in
                    do { try store.complete(workout.id, completion: completion) } catch { env.alert = .dataError }
                    env.notifications.cancel(for: workout.id)
                    await env.refreshSideEffects()
                }
            }
        } else {
            EmptyStateView(systemImage: "questionmark.circle", title: "Workout unavailable", message: "This session is no longer in your plan.")
        }
    }

    // MARK: - Sections

    private func headerSection(_ w: ScheduledWorkout) -> some View {
        Section {
            HStack(spacing: Theme.Space.m) {
                SportBadge(sport: w.sport)
                VStack(alignment: .leading) {
                    Text(w.plannedStart, format: .dateTime.weekday(.wide).month().day().hour().minute())
                        .font(.subheadline).foregroundStyle(.secondary)
                    HStack(spacing: Theme.Space.s) {
                        MetricPill(systemImage: "clock", text: fmt.duration(minutes: w.effectivePlannedMinutes))
                        if let d = fmt.distance(w.plannedDistanceMeters, sport: w.sport) { MetricPill(systemImage: "ruler", text: d) }
                        MetricPill(systemImage: "gauge.medium", text: fmt.intensity(w.intensity))
                    }
                }
                Spacer()
            }
            if w.status != .planned { StatusChip(status: w.status) }
        }
    }

    private func purposeSection(_ w: ScheduledWorkout) -> some View {
        Section("Purpose") {
            Text(w.objective).font(.body)
            Label("\(w.stressCategory.englishName) session · \(fmt.rpeHint(w.intensity))", systemImage: "figure.run")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private func stepSection(_ title: String, _ symbol: String, _ steps: [WorkoutStep]) -> some View {
        if !steps.isEmpty {
            Section {
                ForEach(steps) { step in StepRow(step: step, fmt: fmt) }
            } header: {
                SectionLabel(title: title, systemImage: symbol)
            }
        }
    }

    @ViewBuilder private func cuesSection(_ t: WorkoutTemplate) -> some View {
        if !t.techniqueCues.isEmpty {
            Section("Technique") {
                ForEach(t.techniqueCues, id: \.self) { Label($0, systemImage: "sparkles").font(.callout) }
            }
        }
    }

    @ViewBuilder private func fuelingSection(_ t: WorkoutTemplate) -> some View {
        if t.fueling != nil || t.hydration != nil {
            Section("Fueling & hydration") {
                if let f = t.fueling {
                    if let lo = f.carbsGramsPerHourLow, let hi = f.carbsGramsPerHourHigh {
                        Label("\(lo)–\(hi) g carbohydrate per hour", systemImage: "fork.knife")
                    }
                    if let note = f.note { Text(note).font(.footnote).foregroundStyle(.secondary) }
                }
                if let h = t.hydration {
                    if let lo = h.fluidsMillilitresPerHourLow, let hi = h.fluidsMillilitresPerHourHigh {
                        Label("\(lo)–\(hi) mL fluid per hour", systemImage: "drop")
                    }
                    if let note = h.note { Text(note).font(.footnote).foregroundStyle(.secondary) }
                }
                Text("Targets, not prescriptions. Practice your race-day plan; don’t overdrink.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private func gearSafetySection(_ t: WorkoutTemplate) -> some View {
        if !t.gear.isEmpty || !t.safetyNotes.isEmpty {
            Section("Gear & safety") {
                ForEach(t.gear, id: \.self) { Label($0, systemImage: "bag") }
                ForEach(t.safetyNotes, id: \.self) { Label($0, systemImage: "exclamationmark.shield").foregroundStyle(.orange) }
            }
        }
    }

    private func statusSection(_ w: ScheduledWorkout) -> some View {
        Section("Your session") {
            if let c = w.completion {
                if let m = c.actualDurationMinutes { LabeledContent("Logged duration", value: fmt.duration(minutes: m)) }
                if let rpe = c.perceivedExertion { LabeledContent("Perceived exertion", value: "\(rpe)/10") }
                if let notes = c.notes { LabeledContent("Notes", value: notes) }
                Label("Source: \(c.source.rawValue)", systemImage: "square.and.pencil").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Not logged yet.").foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private func historySection(_ w: ScheduledWorkout) -> some View {
        if !w.modifications.isEmpty {
            Section("Modification history") {
                ForEach(w.modifications) { m in
                    Label {
                        VStack(alignment: .leading) {
                            Text(m.type.rawValue.capitalized)
                            Text(m.createdAt, format: .dateTime.month().day().hour().minute())
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    } icon: { Image(systemName: "clock.arrow.circlepath") }
                }
            }
        }
    }
}

/// Renders one structured step, expanding repeats as "N ×".
struct StepRow: View {
    let step: WorkoutStep
    let fmt: DisplayFormatter

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack {
                if step.repeats > 1 { Text("\(step.repeats) ×").font(.headline).monospacedDigit() }
                Text(step.label).font(.body)
                Spacer()
                Text(goalText).font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
            }
            if let note = step.note {
                Text(note).font(.caption).foregroundStyle(.secondary)
            }
            if !step.childSteps.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(step.childSteps) { child in
                        HStack {
                            Text("•").foregroundStyle(.tertiary)
                            Text(child.label).font(.callout)
                            Spacer()
                            Text(Self.goal(child, fmt: fmt)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.leading, Theme.Space.m)
            }
        }
        .padding(.vertical, 2)
    }

    private var goalText: String { Self.goal(step, fmt: fmt) }

    static func goal(_ s: WorkoutStep, fmt: DisplayFormatter) -> String {
        if let sec = s.durationSeconds, sec > 0 { return fmt.duration(minutes: max(1, sec / 60)) }
        if let m = s.distanceMeters, m > 0 { return "\(Int(m)) m" }
        if s.isOpenGoal { return "as needed" }
        return ""
    }
}
