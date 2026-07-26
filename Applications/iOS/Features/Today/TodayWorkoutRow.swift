import SwiftUI
import EnduranceDomain

struct TodayWorkoutRow: View {
    let workout: ScheduledWorkout
    let fmt: DisplayFormatter

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.m) {
            SportBadge(sport: workout.sport)
                .frame(width: 28)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                HStack {
                    Text(workout.title).font(.headline)
                    if workout.isOptional {
                        Text("Optional").font(.caption2).foregroundStyle(.secondary)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(.quaternary, in: Capsule())
                    }
                    Spacer()
                    Text(DisplayFormatter.time(workout.plannedStart))
                        .font(.subheadline).foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Text(workout.objective)
                    .font(.subheadline).foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack(spacing: Theme.Space.s) {
                    MetricPill(systemImage: "clock", text: fmt.duration(minutes: workout.effectivePlannedMinutes))
                    if let d = fmt.distance(workout.plannedDistanceMeters, sport: workout.sport) {
                        MetricPill(systemImage: "ruler", text: d)
                    }
                    MetricPill(systemImage: "gauge.medium", text: fmt.intensity(workout.intensity))
                }
                .padding(.top, 2)

                if workout.status != .planned {
                    StatusChip(status: workout.status).padding(.top, 2)
                }
            }
        }
        .padding(.vertical, Theme.Space.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        var parts = ["\(workout.sport.englishName): \(workout.title)",
                     "at \(DisplayFormatter.time(workout.plannedStart))",
                     "\(fmt.duration(minutes: workout.effectivePlannedMinutes))",
                     fmt.intensity(workout.intensity)]
        if workout.status != .planned { parts.append("status \(workout.status.englishName)") }
        return parts.joined(separator: ", ")
    }
}
