import WidgetKit
import SwiftUI
import EnduranceDomain

@main
struct EnduranceWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodayWidget()
    }
}

/// "What am I doing today, and why" — on the Home Screen, Lock Screen and the
/// Watch face (§K).
///
/// This is the cheap answer to the question a watchOS app would otherwise be
/// built to answer. It reads the compact snapshot the app writes to the shared
/// App Group container; it never opens SwiftData. A timeline refresh must not
/// run a migration or fault in 382 workouts.
struct TodayWidget: Widget {
    let kind = "TodayWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TodayTimelineProvider()) { entry in
            TodayWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Today")
        .description("Your next session and how the week is going.")
        .supportedFamilies([
            .systemSmall, .systemMedium,
            .accessoryRectangular, .accessoryInline, .accessoryCircular,
        ])
    }
}

// MARK: - Timeline

struct TodayEntry: TimelineEntry {
    let date: Date
    let snapshot: SharedTodaySnapshot?
    /// True when the App Group itself is unreachable, which is a different
    /// problem from "no plan yet" and must not be rendered as the same thing.
    let isUnavailable: Bool
}

struct TodayTimelineProvider: TimelineProvider {
    private let store = SharedSnapshotStore()

    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(date: Date(), snapshot: .placeholder, isUnavailable: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        completion(currentEntry())
    }

    /// Refresh at the next session's start, or hourly.
    ///
    /// Deliberately not a fixed short interval: WidgetKit budgets refreshes, and
    /// spending them on a plan that changes a few times a day would mean the
    /// widget is stale exactly when it matters. The app also reloads timelines
    /// directly whenever the plan changes, so this is a backstop rather than the
    /// primary path.
    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let entry = currentEntry()
        let nextStart = entry.snapshot?.nextWorkoutStart
        let hourly = Date().addingTimeInterval(3600)
        let refresh = [nextStart, hourly].compactMap { $0 }.filter { $0 > Date() }.min() ?? hourly
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }

    private func currentEntry() -> TodayEntry {
        guard store.isContainerAvailable else {
            return TodayEntry(date: Date(), snapshot: nil, isUnavailable: true)
        }
        return TodayEntry(date: Date(), snapshot: store.read(), isUnavailable: false)
    }
}
