import SwiftUI
import EnduranceDomain

/// The shape of a training week, at a glance.
///
/// Replaces a flat progress bar plus two lines of dense text. A single fraction
/// says how much of the week is done but nothing about how it is *arranged* —
/// and arrangement is what an athlete actually looks for: where the long day
/// falls, whether tomorrow is hard, how much is left after today.
///
/// Bar height carries planned volume, so a four-hour ride is visibly taller than
/// a mobility session. Equal bars would claim every day is the same, which is
/// the opposite of what a training week looks like.
///
/// Deliberately the same visual language as the medium widget, so the week does
/// not appear as two unrelated charts depending on where it is seen.
struct WeekStripView: View {
    let week: Int
    let store: WorkoutStore
    /// Compact drops the summary line, for use inside an already-dense header.
    var showsSummary = true

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private struct Day: Identifiable {
        let id: Int
        let initial: String
        let planned: Int
        let completed: Int
        let isToday: Bool
        let isRest: Bool
        var fraction: Double {
            guard planned > 0 else { return 0 }
            return min(1, Double(completed) / Double(planned))
        }
    }

    private var calendar: Calendar { store.configuration?.calendar ?? .current }

    private var isRecovery: Bool {
        store.plan?.weeks.first { $0.weekNumber == week }?.load == .recovery
    }

    private var days: [Day] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let today = calendar.startOfDay(for: Date())
        return Dictionary(grouping: store.workouts(inWeek: week), by: \.weekdayOffset)
            .sorted { $0.key < $1.key }
            .map { offset, workouts in
                let date = workouts.first.map { calendar.startOfDay(for: $0.scheduledDate) }
                let index = date.map { calendar.component(.weekday, from: $0) - 1 } ?? 0
                let required = workouts.filter { !$0.isOptional }
                return Day(
                    id: offset,
                    initial: symbols.indices.contains(index) ? symbols[index] : "",
                    planned: required.reduce(0) { $0 + $1.plannedDurationMinutes },
                    completed: workouts.filter { $0.status.countsAsDone }
                        .reduce(0) { $0 + $1.plannedDurationMinutes },
                    isToday: date == today,
                    isRest: required.isEmpty)
            }
    }

    var body: some View {
        let days = days
        let peak = max(1, days.map(\.planned).max() ?? 1)
        let progress = ProgressCalculator().weekProgress(week, in: store.allWorkouts)
        let fmt = DisplayFormatter(units: store.units)

        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            // At accessibility sizes the bars become unreadable decoration and
            // the summary line carries everything that matters, so the chart
            // yields rather than shrinking into noise.
            if !dynamicTypeSize.isAccessibilitySize {
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(days) { day in
                        VStack(spacing: 3) {
                            ZStack(alignment: .bottom) {
                                Capsule().fill(.quaternary)
                                    .frame(height: height(day.planned, peak: peak))
                                Capsule()
                                    .fill(fill(for: day))
                                    .frame(height: height(day.planned, peak: peak) * day.fraction)
                            }
                            .frame(maxWidth: .infinity)
                            Text(day.initial)
                                .font(.system(size: 10, weight: day.isToday ? .bold : .regular))
                                .foregroundStyle(day.isToday ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                        }
                    }
                }
                .frame(height: 52)
            }

            if showsSummary {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(fmt.duration(minutes: progress.completedMinutes)) of \(fmt.duration(minutes: progress.plannedMinutes))")
                        .monospacedDigit()
                    if isRecovery {
                        // Text, not colour, states that lower volume is intended.
                        Text("· Recovery week")
                    }
                    Spacer(minLength: Theme.Space.s)
                    Text("\(progress.completedSessionCount)/\(progress.sessionCount)")
                        .monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(progress))
    }

    /// A rest day keeps a visible stub so the week reads as seven days rather
    /// than a gap where something is missing.
    private func height(_ minutes: Int, peak: Int) -> CGFloat {
        guard minutes > 0 else { return 4 }
        return 8 + 30 * CGFloat(minutes) / CGFloat(peak)
    }

    private func fill(for day: Day) -> AnyShapeStyle {
        if day.isToday { return AnyShapeStyle(.tint) }
        return AnyShapeStyle(isRecovery ? Color.purple : Color.secondary)
    }

    private func accessibilityLabel(_ p: ProgressCalculator.WeekProgress) -> String {
        let base = String(localized: "Week \(week): \(p.completedSessionCount) of \(p.sessionCount) sessions done")
        return isRecovery ? base + ", " + String(localized: "recovery week") : base
    }
}
