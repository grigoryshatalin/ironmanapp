#if DEBUG
import SwiftUI
import EnduranceDomain

/// Closes the Release 1 notification hardware gate by making the pending set
/// observable.
///
/// Delivery and deep linking were verified with the test reminder. The other
/// three gate items — non-duplication, regeneration and cancellation — are all
/// statements about what iOS is *holding*, not about what arrives, so none of
/// them requires waiting for a reminder to fire. Each is a read of
/// `pendingNotificationRequests()` plus an action, which turns a multi-hour
/// wall-clock exercise into a few seconds of tapping.
///
/// Debug builds only. This inspects state; it never fabricates it.
struct NotificationDiagnosticsView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(WorkoutStore.self) private var store

    @State private var pending: [NotificationScheduler.PendingReminder] = []
    @State private var beforeCount: Int?
    @State private var resyncOutcome: String?
    @State private var isWorking = false

    var body: some View {
        List {
            Section {
                LabeledContent("Pending reminders") {
                    Text("\(pending.count)").foregroundStyle(.secondary)
                }
                .accessibilityIdentifier(A11y.Notifications.pendingCount)

                if pending.count >= 64 {
                    Text("At the iOS limit of 64. The planner caps and refreshes, so this is expected on a full plan.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            } header: {
                Text("What iOS is holding")
            }

            Section {
                Button("Re-sync (proves non-duplication)") {
                    Task { await checkNonDuplication() }
                }
                .disabled(isWorking)
                .accessibilityIdentifier(A11y.Notifications.resync)

                if let resyncOutcome {
                    Text(resyncOutcome).font(.footnote).foregroundStyle(.secondary)
                        .accessibilityIdentifier(A11y.Notifications.resyncResult)
                }
            } footer: {
                Text("Syncs again with identical input. Identifiers are derived, not random, so a correct reconcile leaves the set unchanged.")
            }

            Section("Pending") {
                if pending.isEmpty {
                    Text("Nothing scheduled.").foregroundStyle(.secondary)
                }
                ForEach(pending) { reminder in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(reminder.title).font(.callout)
                        if let fire = reminder.fireDate {
                            Text(fire, format: .dateTime.weekday().month().day().hour().minute())
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Text(reminder.id)
                            .font(.caption2.monospaced()).foregroundStyle(.tertiary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                }
            }
        }
        .navigationTitle("Notification diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await reload() }
        .task { await reload() }
    }

    private func reload() async {
        pending = await env.notifications.pendingReminders()
    }

    /// The gate item that stable identifiers exist to guarantee: syncing twice
    /// must not double the pending set.
    private func checkNonDuplication() async {
        isWorking = true
        defer { isWorking = false }

        let before = await env.notifications.pendingReminders()
        beforeCount = before.count

        await env.notifications.resync(
            workouts: store.allWorkouts,
            preferences: store.notificationPreferences,
            calendar: store.configuration?.calendar ?? .current)

        let after = await env.notifications.pendingReminders()
        pending = after

        let beforeIDs = Set(before.map(\.id))
        let afterIDs = Set(after.map(\.id))
        if beforeIDs == afterIDs {
            resyncOutcome = "PASS — \(after.count) reminders, identical identifiers."
        } else {
            let added = afterIDs.subtracting(beforeIDs).count
            let removed = beforeIDs.subtracting(afterIDs).count
            resyncOutcome = "CHANGED — \(added) added, \(removed) removed (\(before.count) → \(after.count))."
        }
    }
}
#endif
