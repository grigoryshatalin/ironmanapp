import SwiftUI
import EnduranceDomain

/// A quiet, non-judgmental weekly progress indicator: completed vs planned time.
/// Recovery weeks are labelled so lower volume reads as intended, not as failure.
struct WeekProgressBar: View {
    let week: Int
    let store: WorkoutStore

    private var progress: ProgressCalculator.WeekProgress {
        ProgressCalculator().weekProgress(week, in: store.allWorkouts)
    }
    private var isRecovery: Bool {
        store.plan?.weeks.first { $0.weekNumber == week }?.load == .recovery
    }

    private func accessibilityText(_ p: ProgressCalculator.WeekProgress) -> String {
        let base = String(localized: "Week \(week): \(p.completedSessionCount) of \(p.sessionCount) sessions done")
        guard isRecovery else { return base }
        return base + ", " + String(localized: "recovery week")
    }

    var body: some View {
        let p = progress
        let fmt = DisplayFormatter(units: store.units)
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            ProgressView(value: p.completionFraction)
                .tint(isRecovery ? .purple : .accentColor)
            HStack(alignment: .firstTextBaseline) {
                Text("\(fmt.duration(minutes: p.completedMinutes)) of \(fmt.duration(minutes: p.plannedMinutes))")
                    .monospacedDigit()
                if isRecovery {
                    // Text, not a color, states that lower volume is intended.
                    Text("· Recovery week")
                }
                Spacer(minLength: Theme.Space.s)
                Text("\(p.completedSessionCount)/\(p.sessionCount) sessions")
                    .monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText(p))
    }
}
