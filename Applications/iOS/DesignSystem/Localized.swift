import Foundation
import SwiftUI
import EnduranceDomain

/// Resolves the domain's `localizationKey` values against the app's String
/// Catalog.
///
/// The domain layer deliberately ships no user-facing English: its
/// `englishName` properties exist as developer-facing fallbacks for logs and
/// tests, and must not reach the UI. Everything the athlete reads resolves
/// through here, so adding a language is a translation task rather than a code
/// change (§28.18).
///
/// These keys are looked up dynamically, so the compiler cannot extract them.
/// They are therefore seeded in `Localizable.xcstrings` with
/// `extractionState: manual` — do not delete them as "unused".
enum Localized {

    static func string(_ key: String) -> String {
        let value = String(localized: String.LocalizationValue(key), bundle: .main)
        // A missing key resolves to the key itself; surface that in debug rather
        // than shipping "sport.swim" to a user.
        #if DEBUG
        if value == key {
            AppLog.app.error("Missing localization for key: \(key, privacy: .public)")
        }
        #endif
        return value
    }

    static func text(_ key: String) -> Text { Text(verbatim: string(key)) }
}

// MARK: - Domain conveniences

extension Sport {
    var localizedName: String { Localized.string(localizationKey) }
}

extension IntensityZone {
    var localizedName: String { Localized.string(localizationKey) }
}

extension StressCategory {
    var localizedName: String { Localized.string(localizationKey) }
}

extension WorkoutStatus {
    var localizedName: String { Localized.string(localizationKey) }
}

extension MeasurementSystem {
    var localizedName: String { Localized.string(localizationKey) }
}

extension WeekLoad {
    var localizedName: String { Localized.string(localizationKey) }
}

extension NotificationCategory {
    var localizedName: String { Localized.string(localizationKey) }
}

extension ModificationType {
    var localizedName: String { Localized.string(localizationKey) }
}

extension CompletionSource {
    var localizedName: String { Localized.string(localizationKey) }
}

extension StepKind {
    var localizedName: String { Localized.string(localizationKey) }
}

// MARK: - Release 2 integration types

extension HealthCapability {
    var localizedName: String { Localized.string(localizationKey) }
}

extension WorkoutProvider {
    var localizedName: String { Localized.string(localizationKey) }
}

extension WorkoutMatcher.Confidence {
    var localizedName: String { Localized.string(localizationKey) }
}

extension ActiveWorkoutState {
    var localizedName: String { Localized.string(localizationKey) }
}

extension WorkoutKitConversionOutcome {
    var localizedName: String { Localized.string(localizationKey) }
}

extension WorkoutKitConversionWarning {
    var localizedName: String { Localized.string(localizationKey) }
}

extension WorkoutSchedulingAuthorization {
    var localizedName: String { Localized.string(localizationKey) }
}

extension WorkoutKitScheduleStatus {
    var localizedName: String { Localized.string(localizationKey) }
}

extension WorkoutKitSchedulingHorizon {
    var localizedName: String { Localized.string(localizationKey) }
}

extension WorkoutKitUnsupportedReason {
    var localizedName: String { Localized.string(localizationKey) }
}
