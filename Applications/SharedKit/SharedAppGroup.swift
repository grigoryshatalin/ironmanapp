import Foundation
import EnduranceDomain

/// The App Group both the app and its extensions read and write through.
///
/// A literal, and deliberately not derived from `Bundle.main.bundleIdentifier`:
/// the widget extension has a *different* bundle identifier from the app, so
/// deriving it would give the two targets different containers and the widget
/// would silently find nothing.
///
/// This carried the template's `com.example` prefix until it was corrected —
/// an unregistered group makes `containerURL(forSecurityApplicationGroupIdentifier:)`
/// return nil, and the writer then does nothing at all, with no error.
public enum SharedAppGroup {
    public static let identifier = "group.com.grigoryshatalin.endurance"
}

/// Reads and writes the compact "today" snapshot in the shared container (§28.19).
///
/// Deliberately a plain JSON file rather than the SwiftData store: a widget
/// timeline refresh must not open the full database, and the extension has no
/// business running migrations. Best-effort and non-fatal in both directions —
/// a widget that cannot read shows its placeholder rather than failing.
public struct SharedSnapshotStore: Sendable {
    private let appGroupID: String
    private let filename = "today-snapshot.json"

    public init(appGroupID: String = SharedAppGroup.identifier) {
        self.appGroupID = appGroupID
    }

    private var url: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(filename)
    }

    /// Whether the shared container is reachable at all.
    ///
    /// Distinguishes "no snapshot yet" from "this build cannot see the App
    /// Group", which are otherwise identical from the widget's side and were the
    /// cause of a silent failure once already.
    public var isContainerAvailable: Bool { url != nil }

    public func write(_ snapshot: SharedTodaySnapshot) {
        guard let url else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
    }

    public func read() -> SharedTodaySnapshot? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(SharedTodaySnapshot.self, from: data)
    }
}
