import Foundation
import EnduranceDomain

/// Product-level configuration, isolated so the app can be renamed or re-bundled
/// without touching feature code (brief: keep the name isolated in configuration).
enum AppConfig {
    /// Display name. Sourced from the domain so there's a single source of truth.
    static let productName = EnduranceDomain.productName

    /// App Group container id shared with widgets / watch / intents.
    static let appGroupIdentifier = SharedAppGroup.identifier

    /// This app's bundle id. Used to recognise Endurance's own HealthKit
    /// exports so they are never re-imported as if they came from elsewhere
    /// (§O). Read from the bundle so a rename cannot silently break that check.
    static let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.grigoryshatalin.endurance"

    /// URL scheme for notification deep links (must match Info.plist).
    static let deepLinkScheme = "endurance"

    /// Notification category identifiers (registered once at launch).
    enum NotificationCategoryID {
        static let workout = "WORKOUT"
        static let review = "WEEKLY_REVIEW"
    }

    /// Notification action identifiers (must be globally unique).
    enum NotificationActionID {
        static let markComplete = "MARK_COMPLETE"
        static let openWorkout = "OPEN_WORKOUT"
    }
}
