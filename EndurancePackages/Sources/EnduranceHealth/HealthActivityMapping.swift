import Foundation
import EnduranceDomain

/// Maps between HealthKit workout activity types and Endurance sports (§D).
///
/// Deliberately expressed over `HKWorkoutActivityType.rawValue` (a `UInt`)
/// rather than the HealthKit enum itself. HealthKit is unavailable on macOS, so
/// referencing the enum here would make this logic untestable under
/// `swift test` — and this is precisely the logic that decides whether a swim
/// gets filed as a run. The adapter passes `type.rawValue` straight through.
///
/// The raw values are Apple's documented, ABI-stable `HKWorkoutActivityType`
/// constants; they are part of the persisted HealthKit format and do not change.
public enum HealthActivityMapping {

    /// Activity types Endurance imports, mapped to the sport it files them under.
    ///
    /// The map is deliberately explicit and closed (§D: "other workout types
    /// only through an explicit mapping"). An unknown activity is *not* guessed
    /// at — it is skipped, so a yoga session never lands as a threshold run.
    public static let supported: [UInt: Sport] = [
        46: .swim,           // .swimming
        84: .swim,           // .waterSports — pool/open-water adjacent
        13: .bike,           // .cycling
        37: .run,            // .running
        52: .recovery,       // .walking — stands in for recovery/easy movement
        50: .strength,       // .traditionalStrengthTraining
        20: .strength,       // .functionalStrengthTraining
        80: .strength,       // .coreTraining
        // Endurance schedules strength sessions to the Watch as HIIT, because
        // that is the only Watch activity that carries interval structure. A
        // session completed there returns as HIIT, so it must map back to
        // strength or it would be dropped as unmapped and never match its
        // planned session. The consequence is accepted deliberately: a HIIT
        // workout the athlete does independently also files as strength.
        63: .strength,       // .highIntensityIntervalTraining
        16: .mobility,       // .flexibility
        75: .mobility,       // .yoga
        59: .mobility,       // .preparationAndRecovery
        82: .brick,          // .transition — multisport transition
    ]

    /// Activity types that indicate a multisport/triathlon container.
    public static let multisport: Set<UInt> = [
        82,  // .transition
        76,  // .swimBikeRun
    ]

    /// The sport an imported activity should be filed under, or `nil` when the
    /// activity is not one Endurance tracks.
    public static func sport(forActivityRawValue raw: UInt) -> Sport? {
        supported[raw]
    }

    public static func isMultisport(_ raw: UInt) -> Bool {
        multisport.contains(raw)
    }

    /// The activity type Endurance writes when exporting a session (§F).
    /// Returns `nil` for sports with no sensible HealthKit representation, so
    /// the caller refuses the export rather than filing it under something wrong.
    public static func activityRawValue(for sport: Sport) -> UInt? {
        switch sport {
        case .swim: return 46
        case .bike: return 13
        case .run: return 37
        case .strength: return 50
        case .mobility: return 16
        case .recovery: return 52
        // A brick or a race is a multisport session; Endurance keeps the full
        // structure locally and does not attempt to synthesise a container.
        case .brick, .race: return nil
        }
    }
}

/// Which HealthKit capability each sport's distance lives under, so the importer
/// requests only what it uses (§C: no broad permissions "for future use").
public enum HealthCapabilityPlan {

    /// The minimum set needed for import to be useful at all.
    public static let coreImport: [HealthCapability] = [
        .workouts, .heartRate, .activeEnergy,
        .runningDistance, .cyclingDistance, .swimmingDistance,
    ]

    /// Requested only once a feature that displays them exists.
    public static let extendedMetrics: [HealthCapability] = [
        .restingHeartRate, .cyclingPower, .runningPower,
    ]

    /// Requested only when route recording ships.
    public static let routes: [HealthCapability] = [.workoutRoute]

    /// What Endurance writes.
    public static let export: [HealthCapability] = [.workouts, .activeEnergy]

    /// Read capabilities relevant to a given sport, used to explain *why* a
    /// permission is being asked for at the moment it is asked.
    public static func readCapabilities(for sport: Sport) -> [HealthCapability] {
        switch sport {
        case .swim: return [.workouts, .heartRate, .swimmingDistance, .activeEnergy]
        case .bike: return [.workouts, .heartRate, .cyclingDistance, .activeEnergy]
        case .run: return [.workouts, .heartRate, .runningDistance, .activeEnergy]
        case .strength, .mobility, .recovery: return [.workouts, .heartRate, .activeEnergy]
        case .brick, .race: return coreImport
        }
    }
}

/// Decides whether an imported activity is worth surfacing at all (§D).
public enum HealthImportFilter {

    /// Floor for surfacing an imported activity.
    ///
    /// This was 5 minutes, on the assumption that anything shorter was "almost
    /// always accidental starts or stray Watch taps". That was wrong, and it was
    /// wrong silently: a deliberately logged 1-minute core session is real
    /// training, and it vanished with no explanation — indistinguishable from
    /// the feature being broken. Found by using the app, not by any test.
    ///
    /// 30 seconds still screens genuinely accidental taps, which are ended
    /// almost immediately, while keeping short deliberate work. Anything
    /// filtered is now reported rather than dropped in silence.
    public static let minimumDurationSeconds = 30

    public static func isWorthImporting(_ summary: ExternalWorkoutSummary) -> Bool {
        guard !summary.isDeletedAtSource else { return false }
        guard summary.durationSeconds >= minimumDurationSeconds else { return false }
        return true
    }

    /// Endurance must not re-import a workout it wrote itself, or it would
    /// appear twice — once as the local execution and once as an import (§O).
    public static func isSelfAuthored(_ summary: ExternalWorkoutSummary, appBundleID: String) -> Bool {
        summary.sourceBundleIdentifier == appBundleID
    }
}
