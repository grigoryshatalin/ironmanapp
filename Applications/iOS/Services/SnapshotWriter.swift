import Foundation
import EnduranceDomain

/// Writes the compact `SharedTodaySnapshot` to the App Group container so widgets
/// / intents / the watch can read "today" cheaply without opening SwiftData
/// (brief §28.19). Best-effort and non-fatal.
struct SnapshotWriter {
    let appGroupID: String
    private let filename = "today-snapshot.json"

    private var url: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(filename)
    }

    func write(_ snapshot: SharedTodaySnapshot) {
        guard let url else { return }
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(snapshot).write(to: url, options: .atomic)
        } catch {
            AppLog.app.error("Snapshot write failed: \(error)")
        }
    }

    func read() -> SharedTodaySnapshot? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(SharedTodaySnapshot.self, from: data)
    }
}
