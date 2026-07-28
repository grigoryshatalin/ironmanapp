import SwiftUI
import EnduranceDomain

/// The live session screen (§G).
///
/// Shows only fields this device can actually fill — `availableFields` comes
/// from the session's declared capability, so an iPhone without a Watch shows
/// elapsed time and says plainly that it is not recording heart rate, rather
/// than presenting a dash where a number belongs for an hour.
struct ActiveWorkoutView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    let workout: ScheduledWorkout

    @State private var showDiscardConfirmation = false

    private var coordinator: ActiveWorkoutCoordinator { env.activeWorkout }

    var body: some View {
        VStack(spacing: 24) {
            header
            elapsed
            if !coordinator.intervalProgress.isComplete { intervalSection }
            metricsGrid
            Spacer(minLength: 0)
            controls
        }
        .padding()
        .navigationTitle(workout.title)
        .navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled(coordinator.state.isActive)
        .task {
            if coordinator.state == .idle { await coordinator.prepare(workout) }
        }
        .confirmationDialog(
            "Discard this session?",
            isPresented: $showDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button("Discard", role: .destructive) {
                Task { await coordinator.discard(); coordinator.reset(); dismiss() }
            }
            Button("Keep recording", role: .cancel) {}
        } message: {
            Text("Nothing will be saved. This can’t be undone.")
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: 4) {
            Text(stateLabel)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .accessibilityIdentifier(A11y.ActiveWorkout.state)
            if !coordinator.capability.hasLiveSession {
                Text("Recording time on this iPhone. Heart rate and distance need Apple Watch.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier(A11y.ActiveWorkout.capabilityNote)
            }
        }
    }

    private var elapsed: some View {
        Text(format(coordinator.metrics.activeSeconds))
            .font(.system(size: 64, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .contentTransition(.numericText())
            .accessibilityIdentifier(A11y.ActiveWorkout.elapsed)
            .accessibilityLabel("Elapsed \(accessibleDuration(coordinator.metrics.activeSeconds))")
    }

    @ViewBuilder private var intervalSection: some View {
        let progress = coordinator.intervalProgress
        VStack(spacing: 6) {
            if let current = progress.current {
                Text(current.label).font(.headline)
                if let remaining = progress.remainingSeconds {
                    Text("\(format(remaining)) left").font(.subheadline).foregroundStyle(.secondary)
                } else if let meters = progress.remainingMeters {
                    Text("\(Int(meters)) m left").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            if let upcoming = progress.upcoming {
                Text("Next: \(upcoming.label)").font(.footnote).foregroundStyle(.tertiary)
            }
            Text("Step \(min(progress.currentIndex + 1, progress.totalSteps)) of \(progress.totalSteps)")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(A11y.ActiveWorkout.interval)
    }

    private var metricsGrid: some View {
        let fields = coordinator.availableFields.subtracting([.elapsed])
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
            ForEach(Array(fields).sorted(by: { $0.rawValue < $1.rawValue }), id: \.self) { field in
                VStack(spacing: 2) {
                    Text(value(for: field)).font(.title3.monospacedDigit())
                    Text(label(for: field)).font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder private var controls: some View {
        VStack(spacing: 12) {
            switch coordinator.state {
            case .idle, .preparing:
                Button("Start") { Task { await coordinator.start() } }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier(A11y.ActiveWorkout.start)

            case .running:
                HStack(spacing: 12) {
                    Button("Pause") { Task { await coordinator.pause() } }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier(A11y.ActiveWorkout.pause)
                    Button("Lap") { Task { await coordinator.markLap() } }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier(A11y.ActiveWorkout.lap)
                }
                Button("End workout") { Task { await coordinator.end() } }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier(A11y.ActiveWorkout.end)

            case .paused:
                Button("Resume") { Task { await coordinator.resume() } }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier(A11y.ActiveWorkout.resume)
                Button("End workout") { Task { await coordinator.end() } }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier(A11y.ActiveWorkout.end)
                Button("Discard", role: .destructive) { showDiscardConfirmation = true }
                    .accessibilityIdentifier(A11y.ActiveWorkout.discard)

            case .failed:
                // The session is over but the data is not safe yet. Saying so,
                // and offering the retry, is the whole point of keeping it.
                Text("Couldn’t save. Your session is still here — try again.")
                    .font(.footnote).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Try again") { Task { await coordinator.retrySave() } }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier(A11y.ActiveWorkout.retry)
                Button("Discard", role: .destructive) { showDiscardConfirmation = true }

            case .completed:
                Label("Saved", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Button("Done") { coordinator.reset(); dismiss() }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier(A11y.ActiveWorkout.done)

            case .starting, .resuming, .ending, .saving, .recovering:
                ProgressView()

            case .discarded:
                Button("Done") { coordinator.reset(); dismiss() }
                    .accessibilityIdentifier(A11y.ActiveWorkout.done)
            }
        }
    }

    // MARK: - Formatting

    private var stateLabel: String {
        switch coordinator.state {
        case .idle, .preparing: return String(localized: "Ready")
        case .starting: return String(localized: "Starting…")
        case .running: return String(localized: "Recording")
        case .paused: return String(localized: "Paused")
        case .resuming: return String(localized: "Resuming…")
        case .ending, .saving: return String(localized: "Saving…")
        case .completed: return String(localized: "Complete")
        case .discarded: return String(localized: "Discarded")
        case .failed: return String(localized: "Save failed")
        case .recovering: return String(localized: "Recovering…")
        }
    }

    private func label(for field: ActiveWorkoutMetrics.Field) -> String {
        switch field {
        case .elapsed: return String(localized: "Elapsed")
        case .distance: return String(localized: "Distance")
        case .pace: return String(localized: "Pace")
        case .speed: return String(localized: "Speed")
        case .power: return String(localized: "Power")
        case .heartRate: return String(localized: "Heart rate")
        case .energy: return String(localized: "Calories")
        }
    }

    /// An em dash, never a zero. A metric the device did not produce is absent,
    /// and showing "0" would be a measurement the athlete never made.
    private func value(for field: ActiveWorkoutMetrics.Field) -> String {
        let m = coordinator.metrics
        switch field {
        case .elapsed: return format(m.activeSeconds)
        case .distance: return m.distanceMeters.map { String(format: "%.2f km", $0 / 1000) } ?? "—"
        case .pace: return m.averagePaceSecondsPerKilometre.map { format($0) + " /km" } ?? "—"
        case .speed: return m.averageSpeedMetresPerSecond.map { String(format: "%.1f km/h", $0 * 3.6) } ?? "—"
        case .power: return m.currentPowerWatts.map { "\($0) W" } ?? "—"
        case .heartRate: return m.heartRateBPM.map { "\($0) bpm" } ?? "—"
        case .energy: return m.activeEnergyKilocalories.map { "\(Int($0)) kcal" } ?? "—"
        }
    }

    private func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }

    private func accessibleDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let m = total / 60, s = total % 60
        return "\(m) minutes \(s) seconds"
    }
}
