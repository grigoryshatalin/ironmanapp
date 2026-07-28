import AppIntents
import Foundation
import EnduranceDomain

/// Siri, Spotlight and Shortcuts access (§28.17).
///
/// These read the shared snapshot rather than opening SwiftData. An intent can
/// be invoked while the app is not running, and faulting in a 382-workout store
/// to answer "what's my next session" would be slow and, in an extension
/// context, liable to be killed for it.
///
/// Everything here is **read-only or opens the app**. Nothing destructive is
/// exposed to voice: §28.17 requires confirmation for destructive actions, and
/// the honest way to confirm something like "skip today's session" is on screen
/// where the athlete can see what they are changing.

/// What's next, answered without launching the app.
struct NextWorkoutIntent: AppIntent {
    static let title: LocalizedStringResource = "Next workout"
    static let description = IntentDescription(
        "Ask what your next training session is.")
    /// Answers in place; no reason to interrupt what the athlete is doing.
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = SharedSnapshotStore()
        guard store.isContainerAvailable, let snapshot = store.read() else {
            return .result(dialog: "Open Endurance once to set up your plan.")
        }
        guard let title = snapshot.nextWorkoutTitle else {
            return .result(dialog: snapshot.isRecoveryDay
                           ? "Today is a recovery day."
                           : "Nothing else scheduled today.")
        }
        if let start = snapshot.nextWorkoutStart, start > Date() {
            let time = start.formatted(date: .omitted, time: .shortened)
            return .result(dialog: "Next up: \(title) at \(time).")
        }
        return .result(dialog: "Next up: \(title).")
    }
}

/// How today is going, in one sentence.
struct TodayProgressIntent: AppIntent {
    static let title: LocalizedStringResource = "Today's training"
    static let description = IntentDescription(
        "Ask how much of today's training is done.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = SharedSnapshotStore()
        guard store.isContainerAvailable, let s = store.read() else {
            return .result(dialog: "Open Endurance once to set up your plan.")
        }
        guard s.sessionCount > 0 else {
            return .result(dialog: "Nothing scheduled today.")
        }
        if s.completedSessionCount >= s.sessionCount {
            return .result(dialog: "All done — \(s.completedMinutes) minutes today. Week \(s.weekNumber).")
        }
        return .result(dialog: """
            \(s.completedSessionCount) of \(s.sessionCount) sessions done, \
            \(s.completedMinutes) of \(s.plannedMinutes) minutes. Week \(s.weekNumber) of \(s.totalWeeks).
            """)
    }
}

/// Opens the app on today's session.
///
/// Deliberately a separate intent from `NextWorkoutIntent` rather than a
/// parameter on it: "tell me" and "take me there" are different requests, and
/// merging them means one of the two behaves unexpectedly.
struct OpenTodayIntent: AppIntent {
    static let title: LocalizedStringResource = "Open today's training"
    static let description = IntentDescription("Open Endurance on today's session.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        .result()
    }
}

/// Surfaces the intents to Siri and Spotlight without the athlete building a
/// shortcut by hand.
struct EnduranceShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: NextWorkoutIntent(),
            phrases: [
                "What's my next \(.applicationName) workout",
                "Next \(.applicationName) session",
            ],
            shortTitle: "Next workout",
            systemImageName: "figure.run")

        AppShortcut(
            intent: TodayProgressIntent(),
            phrases: [
                "How's my \(.applicationName) training today",
                "\(.applicationName) progress",
            ],
            shortTitle: "Today's training",
            systemImageName: "chart.bar.fill")

        AppShortcut(
            intent: OpenTodayIntent(),
            phrases: ["Open \(.applicationName) today"],
            shortTitle: "Open today",
            systemImageName: "calendar")
    }
}
