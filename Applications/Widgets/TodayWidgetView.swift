import WidgetKit
import SwiftUI
import EnduranceDomain

/// Renders the snapshot across every supported family.
///
/// Each family shows less, not a shrunken version of the same thing: an inline
/// accessory has room for one line, and cramming a progress bar into it would
/// make both illegible. What survives every size is the next session — that is
/// the question the widget exists to answer.
struct TodayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodayEntry

    var body: some View {
        switch family {
        case .accessoryInline: inline
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        case .systemSmall: small
        default: medium
        }
    }

    // MARK: - States

    /// The App Group is unreachable — a build/configuration fault, not an empty
    /// plan. Saying "no sessions" here would be a lie that hides a real defect.
    private var unavailable: some View {
        Label("Open Endurance", systemImage: "exclamationmark.triangle")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private var empty: some View {
        Text("No plan yet")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    // MARK: - Families

    @ViewBuilder private var inline: some View {
        if entry.isUnavailable {
            Text("Endurance")
        } else if let s = entry.snapshot, let title = s.nextWorkoutTitle {
            Label(title, systemImage: symbol(for: s.nextWorkoutSport))
        } else {
            Text("Rest day")
        }
    }

    @ViewBuilder private var circular: some View {
        if let s = entry.snapshot {
            Gauge(value: progressFraction(s)) {
                Image(systemName: symbol(for: s.nextWorkoutSport))
            }
            .gaugeStyle(.accessoryCircularCapacity)
        } else {
            Image(systemName: "figure.run").font(.title2)
        }
    }

    @ViewBuilder private var rectangular: some View {
        if entry.isUnavailable {
            unavailable
        } else if let s = entry.snapshot {
            VStack(alignment: .leading, spacing: 1) {
                Text("Week \(s.weekNumber) · \(s.phaseName)")
                    .font(.caption2).foregroundStyle(.secondary)
                if let title = s.nextWorkoutTitle {
                    Text(title).font(.headline).lineLimit(1)
                    if let start = s.nextWorkoutStart {
                        Text(start, style: .time).font(.caption2).foregroundStyle(.secondary)
                    }
                } else {
                    Text(s.isRecoveryDay ? "Recovery day" : "Nothing scheduled").font(.headline)
                }
            }
        } else {
            empty
        }
    }

    @ViewBuilder private var small: some View {
        if entry.isUnavailable {
            unavailable
        } else if let s = entry.snapshot {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: symbol(for: s.nextWorkoutSport))
                        .font(.title3)
                        .foregroundStyle(.tint)
                    Spacer()
                    Text("W\(s.weekNumber)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if let title = s.nextWorkoutTitle {
                    Text(title).font(.headline).lineLimit(2)
                    if let start = s.nextWorkoutStart {
                        Text(start, style: .time)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    Text(s.isRecoveryDay ? "Recovery day" : "Nothing scheduled")
                        .font(.headline)
                }
                progressBar(s)
            }
        } else {
            empty
        }
    }

    @ViewBuilder private var medium: some View {
        if entry.isUnavailable {
            unavailable
        } else if let s = entry.snapshot {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Week \(s.weekNumber) of \(s.totalWeeks) · \(s.phaseName)")
                        .font(.caption).foregroundStyle(.secondary)
                    if let title = s.nextWorkoutTitle {
                        Label(title, systemImage: symbol(for: s.nextWorkoutSport))
                            .font(.headline).lineLimit(1)
                        if let start = s.nextWorkoutStart {
                            Text(start, style: .time)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    } else {
                        Text(s.isRecoveryDay ? "Recovery day" : "Nothing scheduled")
                            .font(.headline)
                    }
                    Spacer(minLength: 0)
                    progressBar(s)
                }
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(s.completedSessionCount)/\(s.sessionCount)")
                        .font(.title2.weight(.semibold)).monospacedDigit()
                    Text("sessions today").font(.caption2).foregroundStyle(.secondary)
                }
            }
        } else {
            empty
        }
    }

    // MARK: - Pieces

    @ViewBuilder private func progressBar(_ s: SharedTodaySnapshot) -> some View {
        // Minutes rather than session count: a 20-minute mobility session and a
        // four-hour ride are not equal thirds of a day's work.
        if s.plannedMinutes > 0 {
            VStack(alignment: .leading, spacing: 2) {
                ProgressView(value: progressFraction(s))
                    .tint(.accentColor)
                Text("\(s.completedMinutes) of \(s.plannedMinutes) min")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func progressFraction(_ s: SharedTodaySnapshot) -> Double {
        guard s.plannedMinutes > 0 else { return 0 }
        return min(1, Double(s.completedMinutes) / Double(s.plannedMinutes))
    }

    /// Matches the symbols the app uses, so the same session does not appear as
    /// two different sports depending on where it is displayed.
    private func symbol(for sport: Sport?) -> String {
        switch sport {
        case .swim: return "figure.pool.swim"
        case .bike: return "figure.outdoor.cycle"
        case .run: return "figure.run"
        case .strength: return "figure.strengthtraining.traditional"
        case .mobility: return "figure.flexibility"
        case .recovery: return "figure.walk"
        case .brick: return "arrow.triangle.swap"
        case .race: return "flag.checkered"
        case nil: return "calendar"
        }
    }
}
