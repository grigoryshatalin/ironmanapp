import SwiftUI
import EnduranceDomain

/// Points the athlete at the Apple Watch, which is where a session is actually
/// recorded.
///
/// Endurance does not record workouts on iPhone. `HKWorkoutSession` is
/// watchOS-only, so an iPhone can capture elapsed time and nothing else — no
/// heart rate, no distance — while the Watch captures all of it and files the
/// result in Health. Competing with that would mean offering a strictly worse
/// recorder *and* creating a second source of truth to de-duplicate.
///
/// The division: **Apple records, Endurance plans.** This section carries the
/// session across to the Watch and then gets out of the way; the finished
/// workout returns through HealthKit import.
///
/// There is deliberately no "Open on Watch" button. `WorkoutPlan.openInWorkoutApp()`
/// is `@available(iOS, unavailable)` — a phone cannot launch the Watch's Workout
/// app, and a button that silently did nothing would be worse than a sentence
/// saying where to look.
struct WatchHandoffSection: View {
    @Environment(AppEnvironment.self) private var env

    let workout: ScheduledWorkout

    @State private var isSending = false
    /// Resolved once and on change, never per render.
    ///
    /// `status(for:)` runs a SwiftData fetch and `conversion(for:)` regroups
    /// bricks across every workout in the plan and re-runs the converter. As
    /// computed properties they did that on *every* body evaluation — and
    /// SwiftUI re-evaluates on each observable change, so toggling `isSending`
    /// alone triggered a full refetch and reconversion mid-animation. That is
    /// what made this section stutter.
    @State private var status: WorkoutKitScheduleStatus = .notEvaluated
    @State private var unsupportedReasons: [WorkoutKitUnsupportedReason] = []
    @State private var failure: WorkoutKitFailureCategory?

    private var coordinator: WorkoutKitCoordinator { env.workoutKit }

    var body: some View {
        Section {
            switch status {
            case .scheduled:
                sentRow

            case .exactAvailable:
                sendButton(simplified: false)

            case .simplifiedAvailable:
                sendButton(simplified: true)
                Text("Some detail can’t be represented on Apple Watch. You’ll see exactly what changes before it’s sent.")
                    .font(.footnote).foregroundStyle(.secondary)

            case .stale:
                sendButton(simplified: false)
                Text("This was sent before the session changed. Send it again to update your Watch.")
                    .font(.footnote).foregroundStyle(.secondary)

            case .authorizationRequired, .notEvaluated:
                NavigationLink {
                    WorkoutKitSettingsView()
                } label: {
                    Label("Set up Apple Watch", systemImage: "applewatch")
                }
                .accessibilityIdentifier(A11y.Detail.watchSetup)

            case .unsupported:
                unsupportedRow

            case .failedRetryable, .failedPermanent:
                sendButton(simplified: false)
                Text(failureExplanation)
                    .font(.footnote).foregroundStyle(.secondary)
                    .accessibilityIdentifier(A11y.Detail.watchFailure)

            case .scheduling, .rescheduling, .removing:
                HStack { ProgressView(); Text("Sending…").foregroundStyle(.secondary) }

            case .removed:
                sendButton(simplified: false)
            }
        } header: {
            Text("Apple Watch")
        } footer: {
            if status == .scheduled {
                Text("Heart rate, distance and calories are recorded by your Watch. When you finish, the session appears here automatically.")
            }
        }
        .task(id: workout.id) { refresh() }
    }

    // MARK: - Rows

    private var sentRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text("Sent to Apple Watch")
            } icon: {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            }
            .accessibilityIdentifier(A11y.Detail.watchSent)

            // The instruction replaces the button that cannot exist.
            Text("Open the **Workout** app on your Watch — it’s waiting under Scheduled.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func sendButton(simplified: Bool) -> some View {
        Button {
            Task { await send(simplified: simplified) }
        } label: {
            HStack {
                Label(simplified ? "Review and send to Watch" : "Send to Apple Watch",
                      systemImage: "applewatch.radiowaves.left.and.right")
                if isSending { Spacer(); ProgressView() }
            }
        }
        .disabled(isSending)
        .accessibilityIdentifier(A11y.Detail.watchSend)
    }

    private var unsupportedRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Not available on Apple Watch", systemImage: "applewatch.slash")
                .foregroundStyle(.secondary)
            // Say which reason, rather than a generic refusal.
            Text(unsupportedExplanation)
                .font(.footnote).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(A11y.Detail.watchUnsupported)
    }

    private func refresh() {
        status = coordinator.status(for: workout)
        unsupportedReasons = status == .unsupported
            ? coordinator.conversion(for: workout).unsupportedReasons
            : []
        failure = coordinator.lastFailure
    }

    /// Names what actually went wrong. "Didn't finish" tells the athlete
    /// nothing they can act on, and this is the screen where they would act.
    private var failureExplanation: String {
        switch failure {
        case .authorizationRequired, .authorizationDenied:
            return String(localized: "Apple Watch scheduling needs permission. Open Settings to allow it.")
        case .workoutKitUnavailable:
            return String(localized: "This iPhone can’t schedule to Apple Watch.")
        case .duplicatePrevented:
            return String(localized: "This session is already on your Watch.")
        default:
            return String(localized: "Last attempt didn’t reach your Watch. Your plan is unchanged.")
        }
    }

    private var unsupportedExplanation: String {
        let reasons = unsupportedReasons
        if reasons.contains(.brickRequiresLinkedComponents) {
            return String(localized: "A brick is two sessions back to back. Start each part separately on your Watch.")
        }
        if reasons.contains(.raceRequiresStructuredMultisport) {
            return String(localized: "Use your Watch’s own multisport workout for race day.")
        }
        return String(localized: "This session has no structure Apple Watch can follow. Record it however you prefer — it’ll still appear here.")
    }

    private func send(simplified: Bool) async {
        isSending = true
        defer { isSending = false; refresh() }
        if simplified {
            await coordinator.approveSimplification(for: workout)
        } else {
            // Not `synchronize()`: that schedules the horizon window and returns
            // silently when scheduling is switched off, so this button did
            // nothing at all for a session outside the window.
            await coordinator.scheduleNow(workout)
        }
    }
}
