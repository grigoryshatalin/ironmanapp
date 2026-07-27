import Foundation
import EnduranceDomain

/// Device-local persistence for the Release 2 integration toggles.
///
/// Deliberately **not** SwiftData. Two reasons, and the second is the real one:
///
/// 1. `EnduranceSchemaV1` and `V2` both reference the same live model classes,
///    so adding a property to `SDAppSettings` silently changes the declared
///    shape of *every* version at once. An existing store then matches none of
///    them and SwiftData refuses to open it — "Cannot use staged migration with
///    an unknown model version". Expressing a change to an existing entity would
///    require per-version copies of the model classes first.
///
/// 2. More importantly, these toggles *should* be device-local. They gate
///    HealthKit authorization and scheduling to a paired Watch, neither of which
///    syncs between devices. A synced toggle would read "on" on a device that
///    has no permission and no Watch — a state the UI could not honour. Keeping
///    them beside the capability they describe is the correct scope, not a
///    workaround.
///
/// These were previously plain in-memory properties, which meant every launch
/// reset import to off. Because both the importer and the rescan path guard on
/// the toggle, the feature did not present as "disabled" — it presented as
/// broken: an empty Health Inbox and a "Re-scan" button that did nothing.
struct IntegrationPreferences: Equatable {
    var healthImportEnabled = false
    var healthExportEnabled = false
    var healthAutoExportEnabled = false
    var workoutKitEnabled = false
    var workoutKitHorizon: WorkoutKitSchedulingHorizon = .nextWorkout

    /// Whether Endurance has ever put the read-authorization sheet in front of
    /// the athlete.
    ///
    /// This has to be recorded by us. HealthKit reports write authorization
    /// only, and returns `.unknowable` for reads by design — so "have we asked?"
    /// cannot be derived from the framework, and any attempt to infer it is a
    /// guess. The previous code inferred it from the presence of `.unknowable`,
    /// which is constant by construction, so the app believed it had already
    /// asked from the very first launch and never showed the Connect button.
    var hasRequestedHealthAuthorization = false
}

@MainActor
final class IntegrationPreferencesStore {

    private enum Key {
        static let healthImport = "integration.health.import"
        static let healthExport = "integration.health.export"
        static let healthAutoExport = "integration.health.autoExport"
        static let workoutKit = "integration.workoutKit.enabled"
        static let workoutKitHorizon = "integration.workoutKit.horizon"
        static let askedHealth = "integration.health.hasAsked"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> IntegrationPreferences {
        IntegrationPreferences(
            healthImportEnabled: defaults.bool(forKey: Key.healthImport),
            healthExportEnabled: defaults.bool(forKey: Key.healthExport),
            healthAutoExportEnabled: defaults.bool(forKey: Key.healthAutoExport),
            workoutKitEnabled: defaults.bool(forKey: Key.workoutKit),
            workoutKitHorizon: defaults.string(forKey: Key.workoutKitHorizon)
                .flatMap(WorkoutKitSchedulingHorizon.init(rawValue:)) ?? .nextWorkout,
            hasRequestedHealthAuthorization: defaults.bool(forKey: Key.askedHealth))
    }

    func save(_ prefs: IntegrationPreferences) {
        defaults.set(prefs.healthImportEnabled, forKey: Key.healthImport)
        defaults.set(prefs.healthExportEnabled, forKey: Key.healthExport)
        defaults.set(prefs.healthAutoExportEnabled, forKey: Key.healthAutoExport)
        defaults.set(prefs.workoutKitEnabled, forKey: Key.workoutKit)
        defaults.set(prefs.workoutKitHorizon.rawValue, forKey: Key.workoutKitHorizon)
        defaults.set(prefs.hasRequestedHealthAuthorization, forKey: Key.askedHealth)
    }
}
