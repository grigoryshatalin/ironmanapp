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

    var body: some View {
        let p = progress
        let fmt = DisplayFormatter(units: store.units)
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            ProgressView(value: p.completionFraction)
                .tint(isRecovery ? .purple : .accentColor)
            HStack {
                Text("\(fmt.duration(minutes: p.completedMinutes)) of \(fmt.duration(minutes: p.plannedMinutes))")
                if isRecovery {
                    Text("· Recovery week").foregroundStyle(.purple)
                }
                Spacer()
                Text("\(p.completedSessionCount)/\(p.sessionCount) sessions")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Week \(week): \(p.completedSessionCount) of \(p.sessionCount) sessions done" + (isRecovery ? ", recovery week" : ""))
    }
}
