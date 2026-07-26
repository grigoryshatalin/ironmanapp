import Foundation
import OSLog

/// Structured logging. Prefer these over `print`; never swallow errors silently.
enum AppLog {
    private static let subsystem = "com.example.endurance"
    static let app = Logger(subsystem: subsystem, category: "app")
    static let persistence = Logger(subsystem: subsystem, category: "persistence")
    static let notifications = Logger(subsystem: subsystem, category: "notifications")
    static let schedule = Logger(subsystem: subsystem, category: "schedule")
}
