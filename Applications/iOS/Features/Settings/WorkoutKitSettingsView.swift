import SwiftUI
import EnduranceDomain

/// Apple Workout scheduling settings (§M).
///
/// The honesty requirement runs through this screen: authorization state is
/// reported, never assumed; the horizon makes clear that only an upcoming window
/// is synchronized rather than all 382 sessions; and a session that cannot be
/// represented says so plainly instead of appearing to have been scheduled.
struct WorkoutKitSettingsView: View {
    @Environment(AppEnvironment.self) private var env
    private var coordinator: WorkoutKitCoordinator { env.workoutKit }
    private var store: WorkoutStore { env.store }

    @State private var isWorking = false

    var body: some View {
        List {
            statusSection
            if coordinator.isSupported {
                controlsSection
                previewSection
                maintenanceSection
            }
            explanationSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Apple Workout")
        .navigationBarTitleDisplayMode(.inline)
        .task { await coordinator.refreshAuthorization() }
    }

    // MARK: - Status

    @ViewBuilder private var statusSection: some View {
        Section {
            LabeledContent("Scheduling") {
                Text(authorizationDescription)
                    .foregroundStyle(.secondary)
            }
            .accessibilityIdentifier(A11y.WorkoutKit.authorization)

            if let last = coordinator.preferences.lastSuccessfulSynchronization,
               coordinator.preferences.isEnabled {
                LabeledContent("Last synchronized") {
                    Text(last, format: .relative(presentation: .named))
                        .foregroundStyle(.secondary)
                }
                .accessibilityIdentifier(A11y.WorkoutKit.lastSync)
            }

            if let failure = coordinator.lastFailure {
                Label(failureDescription(failure), systemImage: "exclamationmark.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier(A11y.WorkoutKit.failure)
                #if DEBUG
                // The stable failure code, verbatim. The friendly sentence above
                // is deliberately vague about the cause, which makes a real
                // failure impossible to diagnose without attaching a debugger —
                // and WorkoutKit failures only ever happen on a real device with
                // a real Watch, where attaching one is least convenient.
                Text(verbatim: "code: \(failure.rawValue)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
                    .accessibilityIdentifier(A11y.WorkoutKit.failureCode)
                #endif
            }
        } footer: {
            if !coordinator.isSupported {
                Text("This device can’t schedule workouts to the Apple Workout app. Your training plan is unaffected.")
            }
        }
    }

    private var authorizationDescription: String {
        guard coordinator.isSupported else { return String(localized: "Unavailable on this device") }
        if !coordinator.preferences.isEnabled { return String(localized: "Off") }
        return coordinator.authorization.localizedName
    }

    // MARK: - Controls

    private var controlsSection: some View {
        Section {
            Toggle("Schedule to Apple Workout", isOn: enabledBinding)
                .accessibilityIdentifier(A11y.WorkoutKit.enableToggle)

            if coordinator.preferences.isEnabled {
                Picker("How far ahead", selection: horizonBinding) {
                    ForEach(WorkoutKitSchedulingHorizon.allCases, id: \.self) { horizon in
                        Text(horizon.localizedName).tag(horizon)
                    }
                }
                .accessibilityIdentifier(A11y.WorkoutKit.horizon)
            }
        } footer: {
            Text("Endurance sends only the next few sessions, not the whole 36-week plan. Sessions update on your Watch when you complete, move, shorten or skip them.")
        }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { coordinator.preferences.isEnabled },
            set: { on in
                Task {
                    isWorking = true
                    defer { isWorking = false }
                    if on { await coordinator.enableScheduling() }
                    else { await coordinator.disableScheduling() }
                }
            })
    }

    private var horizonBinding: Binding<WorkoutKitSchedulingHorizon> {
        Binding(
            get: { coordinator.preferences.horizon },
            set: { horizon in
                coordinator.preferences.horizon = horizon
                Task { await coordinator.synchronize() }
            })
    }

    // MARK: - Preview

    /// Shows exactly what will and will not transfer, before it does (§I).
    @ViewBuilder private var previewSection: some View {
        let upcoming = previewWorkouts
        if !upcoming.isEmpty {
            Section {
                ForEach(Array(upcoming.enumerated()), id: \.element.id) { index, workout in
                    previewRow(workout, index: index)
                }
            } header: {
                Text("Upcoming sessions")
            } footer: {
                Text("Sessions Apple Workout can’t represent stay in Endurance in full. Nothing is quietly dropped.")
            }
        }
    }

    private var previewWorkouts: [ScheduledWorkout] {
        store.allWorkouts
            .filter { $0.status == .planned && $0.plannedStart >= Date() }
            .sorted { $0.plannedStart < $1.plannedStart }
            .prefix(5)
            .map { $0 }
    }

    @ViewBuilder private func previewRow(_ workout: ScheduledWorkout, index: Int) -> some View {
        let conversion = coordinator.conversion(for: workout)
        let status = coordinator.status(for: workout)

        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack(alignment: .firstTextBaseline) {
                SportBadge(sport: workout.sport)
                VStack(alignment: .leading, spacing: 2) {
                    Text(workout.title)
                    Text(workout.plannedStart,
                         format: .dateTime.weekday(.abbreviated).month().day().hour().minute())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: Theme.Space.s)
                Text(status.localizedName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }

            // Every warning is stated. A simplification the athlete cannot see
            // is a simplification they cannot consent to.
            ForEach(conversion.warnings, id: \.self) { warning in
                Label(warning.localizedName, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(conversion.unsupportedReasons, id: \.self) { reason in
                Label(reason.localizedName, systemImage: "minus.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if conversion.requiresUserConfirmation, coordinator.preferences.isEnabled {
                Button("Send simplified version") {
                    Task { await coordinator.approveSimplification(for: workout) }
                }
                .font(.footnote)
                .accessibilityIdentifier(A11y.WorkoutKit.approve(index))
            }
        }
        .padding(.vertical, Theme.Space.xs)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(A11y.WorkoutKit.previewRow(index))
    }

    // MARK: - Maintenance

    private var maintenanceSection: some View {
        Section {
            Button("Resynchronize now") {
                Task { await coordinator.synchronize() }
            }
            .disabled(!coordinator.preferences.isEnabled || coordinator.isSynchronizing)
            .accessibilityIdentifier(A11y.WorkoutKit.resync)

            Button(role: .destructive) {
                Task { await coordinator.removeAllScheduled() }
            } label: {
                Text("Remove scheduled workouts")
            }
            .accessibilityIdentifier(A11y.WorkoutKit.removeAll)
        } footer: {
            Text("Removing affects only workouts Endurance scheduled. Your plan and history stay exactly as they are.")
        }
    }

    private var explanationSection: some View {
        Section {
            Text("Scheduled sessions appear in the Workout app on your Apple Watch so you can start them without your phone. Technique cues, fueling notes and safety guidance stay in Endurance, because the Workout app has nowhere to show them.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func failureDescription(_ category: WorkoutKitFailureCategory) -> String {
        switch category.classification {
        case .retryable:
            return String(localized: "Last sync didn’t finish. Your plan is unchanged — try again.")
        case .userActionRequired:
            return String(localized: "Scheduling needs your permission in Settings.")
        case .permanentForWorkout:
            return String(localized: "Some sessions can’t be represented in Apple Workout.")
        case .unavailableOnDevice:
            return String(localized: "Apple Workout scheduling isn’t available here.")
        case .internalConsistencyFailure:
            return String(localized: "Endurance is reconciling what’s on your Watch.")
        }
    }
}
