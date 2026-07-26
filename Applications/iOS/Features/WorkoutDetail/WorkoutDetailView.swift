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
    @State private var completionTick = 0

    /// Interval check-off is deliberately *optional* and session-scoped (§9):
    /// it helps you keep your place mid-session, and carries no consequence if
    /// ignored. Keeping it in view state rather than the store means it never
    /// competes with completion as a source of truth, and needs no migration.
    @State private var checkedSteps: Set<UUID> = []

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
                            .accessibilityIdentifier(A11y.Detail.complete)
                    }
                }
            }
            .haptic(.completed, trigger: completionTick)
            .sheet(isPresented: $completing) {
                CompletionSheet(workout: workout, units: store.units) { completion in
                    do { try store.complete(workout.id, completion: completion) }
                    catch { env.alert = .dataError }
                    env.notifications.cancel(for: workout.id)
                    await env.refreshSideEffects()
                    completionTick += 1
                }
            }
        } else {
            EmptyStateView(systemImage: "questionmark.circle",
                           title: "Workout unavailable",
                           message: "This session is no longer in your plan.")
        }
    }

    // MARK: - Sections

    private func headerSection(_ w: ScheduledWorkout) -> some View {
        Section {
            HStack(alignment: .top, spacing: Theme.Space.m) {
                SportBadge(sport: w.sport, size: .detail)
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text(w.plannedStart, format: .dateTime.weekday(.wide).month().day().hour().minute())
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier(A11y.Detail.scheduledDate)
                    MetricLine(parts: [
                        fmt.duration(minutes: w.effectivePlannedMinutes),
                        fmt.distance(w.plannedDistanceMeters, sport: w.sport) ?? "",
                        fmt.intensity(w.intensity),
                    ])
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, Theme.Space.xs)
            if w.status != .planned {
                StatusChip(status: w.status).accessibilityIdentifier(A11y.Detail.status)
            }
        }
    }

    private func purposeSection(_ w: ScheduledWorkout) -> some View {
        Section("Purpose") {
            Text(w.objective).font(.body)
            Label("\(w.stressCategory.localizedName) session · \(fmt.rpeHint(w.intensity))",
                  systemImage: "figure.run")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private func stepSection(_ title: LocalizedStringKey, _ symbol: String, _ steps: [WorkoutStep]) -> some View {
        if !steps.isEmpty {
            Section {
                ForEach(steps) { step in
                    StepRow(step: step,
                            fmt: fmt,
                            isChecked: checkedSteps.contains(step.id),
                            toggle: { toggle(step.id) })
                }
            } header: {
                SectionLabel(title: title, systemImage: symbol)
            }
        }
    }

    private func toggle(_ id: UUID) {
        if checkedSteps.contains(id) { checkedSteps.remove(id) } else { checkedSteps.insert(id) }
    }

    @ViewBuilder private func cuesSection(_ t: WorkoutTemplate) -> some View {
        if !t.techniqueCues.isEmpty {
            Section("Technique") {
                ForEach(t.techniqueCues, id: \.self) { cue in
                    Label(cue, systemImage: "sparkles").font(.callout)
                }
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
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private func gearSafetySection(_ t: WorkoutTemplate) -> some View {
        if !t.gear.isEmpty || !t.safetyNotes.isEmpty {
            Section("Gear & safety") {
                ForEach(t.gear, id: \.self) { item in
                    Label(item, systemImage: "bag")
                }
                ForEach(t.safetyNotes, id: \.self) { note in
                    // Safety text is never color-only: the symbol and the wording
                    // carry the meaning if color is unavailable.
                    Label(note, systemImage: "exclamationmark.shield")
                        .foregroundStyle(.primary)
                }
            }
        }
    }

    private func statusSection(_ w: ScheduledWorkout) -> some View {
        Section("Your session") {
            if let c = w.completion {
                if let m = c.actualDurationMinutes {
                    LabeledContent("Logged duration", value: fmt.duration(minutes: m))
                }
                if let rpe = c.perceivedExertion {
                    LabeledContent("Perceived exertion", value: "\(rpe)/10")
                }
                if let notes = c.notes { LabeledContent("Notes", value: notes) }
                Label(c.source.localizedName, systemImage: "square.and.pencil")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                            Text(m.type.localizedName)
                            Text(m.createdAt, format: .dateTime.month().day().hour().minute())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

/// Renders one structured step, expanding repeats as "N ×".
///
/// The whole row is a check-off control, but nothing depends on it — a session
/// is completed from the toolbar regardless of which steps are ticked.
struct StepRow: View {
    let step: WorkoutStep
    let fmt: DisplayFormatter
    var isChecked: Bool = false
    var toggle: (() -> Void)?

    var body: some View {
        Button {
            toggle?()
        } label: {
            HStack(alignment: .top, spacing: Theme.Space.m) {
                Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(isChecked ? Color.accentColor : Color.secondary)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    HStack(alignment: .firstTextBaseline) {
                        if step.repeats > 1 {
                            Text("\(step.repeats) ×").font(.headline).monospacedDigit()
                        }
                        Text(step.label).font(.body)
                        Spacer(minLength: Theme.Space.s)
                        Text(goalText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    if let note = step.note {
                        Text(note).font(.caption).foregroundStyle(.secondary)
                    }
                    if !step.childSteps.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(step.childSteps) { child in
                                HStack(alignment: .firstTextBaseline) {
                                    Text("•").foregroundStyle(.tertiary)
                                    Text(child.label).font(.callout)
                                    Spacer(minLength: Theme.Space.s)
                                    Text(Self.goal(child, fmt: fmt))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.leading, Theme.Space.m)
                    }
                }
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isChecked ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint(Text("Optional. Marks this step done for your own tracking."))
        .accessibilityIdentifier(A11y.Detail.intervalToggle(step.id.uuidString))
    }

    private var goalText: String { Self.goal(step, fmt: fmt) }

    static func goal(_ s: WorkoutStep, fmt: DisplayFormatter) -> String {
        if let sec = s.durationSeconds, sec > 0 { return fmt.duration(minutes: max(1, sec / 60)) }
        if let m = s.distanceMeters, m > 0 { return String(localized: "\(Int(m)) m") }
        if s.isOpenGoal { return String(localized: "as needed") }
        return ""
    }
}
