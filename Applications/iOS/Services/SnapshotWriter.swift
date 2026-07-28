import Foundation
import WidgetKit
import EnduranceDomain

/// Thin app-side wrapper over `SharedSnapshotStore`, kept so existing call
/// sites read unchanged. The implementation is shared with the widget extension
/// so the two cannot drift into reading and writing different shapes.
struct SnapshotWriter {
    let appGroupID: String

    private var store: SharedSnapshotStore { SharedSnapshotStore(appGroupID: appGroupID) }

    func write(_ snapshot: SharedTodaySnapshot) {
        guard store.isContainerAvailable else {
            AppLog.app.error("App Group container unavailable; widgets will show stale data")
            return
        }
        store.write(snapshot)
        // The timeline policy is an hourly backstop; this is the primary path.
        // Without it a completed session stays on the Home Screen until the next
        // scheduled refresh, which reads as the app having missed it.
        WidgetCenter.shared.reloadAllTimelines()
    }

    func read() -> SharedTodaySnapshot? { store.read() }
}
