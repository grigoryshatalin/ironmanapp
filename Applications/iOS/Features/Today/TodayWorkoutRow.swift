import SwiftUI
import EnduranceDomain

/// One session in a list. Used by Today and by Week detail, so its layout and
/// its VoiceOver reading are defined once.
struct TodayWorkoutRow: View {
    let workout: ScheduledWorkout
    let fmt: DisplayFormatter
    /// Stable position used only for the automation identifier.
    var index: Int?

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.m) {
            SportBadge(sport: workout.sport)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                // Title and time share a line, but the title wraps rather than
                // shrinking the time away at large Dynamic Type.
                HStack(alignment: .firstTextBaseline) {
                    Text(workout.title)
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    if workout.isOptional {
                        Text("Optional")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: Theme.Space.s)
                    Text(DisplayFormatter.time(workout.plannedStart))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Text(workout.objective)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                MetricLine(parts: metricParts, spoken: spokenMetrics)

                if workout.status != .planned {
                    StatusChip(status: workout.status)
                        .padding(.top, 2)
                        .accessibilityIdentifier(index.map(A11y.Today.rowStatus) ?? "")
                }
            }
        }
        .padding(.vertical, Theme.Space.xs)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint(Text("Opens the full session."))
        .accessibilityIdentifier(index.map(A11y.Today.row) ?? "")
    }

    // MARK: - Metadata

    private var metricParts: [String] {
        var parts = [fmt.duration(minutes: workout.effectivePlannedMinutes)]
        if let distance = fmt.distance(workout.plannedDistanceMeters, sport: workout.sport) {
            parts.append(distance)
        }
        parts.append(fmt.intensity(workout.intensity))
        return parts
    }

    /// Spoken separately so VoiceOver reads "45 minutes, 2 kilometres, Zone 2"
    /// rather than running the interpunct-joined line together.
    private var spokenMetrics: [String] { metricParts }

    private var accessibilityText: String {
        var parts = ["\(workout.sport.localizedName): \(workout.title)"]
        if workout.isOptional { parts.append(String(localized: "Optional")) }
        parts.append(String(localized: "at \(DisplayFormatter.time(workout.plannedStart))"))
        parts.append(contentsOf: metricParts)
        parts.append(workout.objective)
        if workout.status != .planned {
            parts.append(String(localized: "Status: \(workout.status.localizedName)"))
        }
        return parts.joined(separator: ", ")
    }
}
