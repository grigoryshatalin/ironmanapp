import Foundation

/// A parsed notification deep link. Kept tiny and total — unknown links resolve
/// to `nil` and are ignored rather than crashing.
enum DeepLink: Equatable {
    case today
    case workout(UUID)
    case review(Int)

    /// Parses a path like `workout/<uuid>`, `review/8`, or `today`.
    init?(path: String) {
        let parts = path.split(separator: "/").map(String.init)
        switch parts.first {
        case "today": self = .today
        case "workout":
            guard parts.count >= 2, let id = UUID(uuidString: parts[1]) else { return nil }
            self = .workout(id)
        case "review":
            guard parts.count >= 2, let week = Int(parts[1]) else { return nil }
            self = .review(week)
        default:
            return nil
        }
    }

    /// Parses a full URL like `endurance://workout/<uuid>`.
    init?(url: URL) {
        guard url.scheme == AppConfig.deepLinkScheme else { return nil }
        let host = url.host.map { $0 + url.path } ?? String(url.path.dropFirst())
        self.init(path: host)
    }
}
