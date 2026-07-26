import SwiftUI
import Charts
import EnduranceDomain

/// Restrained progress summaries with Swift Charts (brief §11). Separate charts
/// per unit; recovery weeks highlighted; never implies more volume is better.
struct ProgressDashboardView: View {
    @Environment(AppEnvironment.self) private var env
    private var store: WorkoutStore { env.store }
    private let calc = ProgressCalculator()

    private var trend: [ProgressCalculator.WeekProgress] {
        Array(calc.weeklyDurationTrend(in: store.allWorkouts).suffix(12))
    }
    private var currentWeek: Int { store.currentWeek(for: Date()) ?? 1 }

    var body: some View {
        List {
            if store.allWorkouts.isEmpty {
                Section { EmptyStateView(systemImage: "chart.xyaxis.line", title: "No history yet", message: "Complete a session and your progress will appear here.") }
            } else {
                durationSection
                completionSection
                consistencySection
                Section {
                    Text("These summaries are informational. Recovery weeks are meant to be lighter — lower volume there is the plan working, not falling behind.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Progress")
    }

    private var durationSection: some View {
        Section("Planned vs completed (minutes)") {
            Chart {
                ForEach(trend, id: \.weekNumber) { wp in
                    BarMark(x: .value("Week", wp.weekNumber), y: .value("Planned", wp.plannedMinutes))
                        .foregroundStyle(.secondary.opacity(0.35))
                        .accessibilityLabel("Week \(wp.weekNumber) planned")
                        .accessibilityValue("\(wp.plannedMinutes) minutes")
                    BarMark(x: .value("Week", wp.weekNumber), y: .value("Completed", wp.completedMinutes))
                        .foregroundStyle(Color.accentColor)
                        .accessibilityLabel("Week \(wp.weekNumber) completed")
                        .accessibilityValue("\(wp.completedMinutes) minutes")
                }
            }
            .chartXScale(domain: .automatic)
            .frame(height: 200)
            .accessibilityLabel("Planned versus completed training minutes by week")
        }
    }

    private var completionSection: some View {
        Section("Completion by sport (this week)") {
            let wp = calc.weekProgress(currentWeek, in: store.allWorkouts)
            ForEach(wp.bySport.filter { $0.sessionCount > 0 }, id: \.sport) { sp in
                HStack {
                    SportBadge(sport: sp.sport)
                    Text(sp.sport.englishName)
                    Spacer()
                    Text("\(sp.completedSessionCount)/\(sp.sessionCount)").foregroundStyle(.secondary).monospacedDigit()
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var consistencySection: some View {
        Section("Consistency (last 4 weeks)") {
            let c = calc.consistency(lastWeeks: 4, endingAt: currentWeek, in: store.allWorkouts)
            HStack {
                Gauge(value: c) { Text("Consistency") }
                    .gaugeStyle(.accessoryLinearCapacity)
                Text("\(Int(c * 100))%").monospacedDigit().foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Consistency over the last four weeks: \(Int(c * 100)) percent")
        }
    }
}
