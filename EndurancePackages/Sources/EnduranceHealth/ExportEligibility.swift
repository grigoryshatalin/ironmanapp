import Foundation
import EnduranceDomain

/// Whether a completed session may be written to HealthKit, and if not, why (§1).
///
/// Deliberately a pure decision with no HealthKit and no SwiftUI. Views render
/// the result; they never work it out. That matters because several of these
/// states are refusals that protect the athlete's Health record — re-exporting
/// an imported workout, or filing a brick as one misleading ride — and a refusal
/// scattered across view code is a refusal that eventually stops happening.
public enum ExportEligibility: Equatable, Sendable, Hashable {

    /// May be written now.
    case eligible
    /// Already has a HealthKit object from a previous export.
    case alreadyExported(providerWorkoutID: String)
    /// Came *from* HealthKit; writing it back would duplicate it.
    case importedFromHealthKit
    /// Recorded by another app or device, which owns the Health record.
    case externallyOwned(sourceName: String?)
    /// Endurance has no honest single-activity representation for this sport.
    case unsupportedSport(Sport)
    /// Brick and race are multisport; one activity would misrepresent them.
    case unsupportedMultisport(Sport)
    /// Missing dates or a nonsensical duration.
    case missingRequiredData(reason: MissingDataReason)
    /// Write authorization has not been granted.
    case permissionRequired
    /// The athlete has export switched off.
    case exportDisabled
    /// A save for this execution is already in flight.
    case currentlySaving
    /// A previous attempt failed in a way worth retrying.
    case failedRetryable(category: ExportFailureCategory)
    /// A previous attempt failed in a way that will not improve on retry.
    case failedPermanent(category: ExportFailureCategory)

    public enum MissingDataReason: String, Sendable, Hashable, Codable {
        case notCompleted
        case missingStart
        case zeroDuration
        case negativeDuration
    }

    /// Only this state may proceed to a save.
    public var canExportNow: Bool {
        if case .eligible = self { return true }
        if case .failedRetryable = self { return true }
        return false
    }

    /// Whether the UI should offer a retry affordance.
    public var isRetryable: Bool {
        if case .failedRetryable = self { return true }
        return false
    }

    /// Whether this is a refusal that protects data, as opposed to a problem.
    /// Used so the UI stays calm rather than alarming (§5).
    public var isBenignRefusal: Bool {
        switch self {
        case .alreadyExported, .importedFromHealthKit, .externallyOwned,
             .unsupportedSport, .unsupportedMultisport, .exportDisabled:
            return true
        case .eligible, .missingRequiredData, .permissionRequired,
             .currentlySaving, .failedRetryable, .failedPermanent:
            return false
        }
    }

    public var localizationKey: String {
        switch self {
        case .eligible: return "export.eligible"
        case .alreadyExported: return "export.alreadyExported"
        case .importedFromHealthKit: return "export.importedFromHealthKit"
        case .externallyOwned: return "export.externallyOwned"
        case .unsupportedSport: return "export.unsupportedSport"
        case .unsupportedMultisport: return "export.unsupportedMultisport"
        case .missingRequiredData: return "export.missingRequiredData"
        case .permissionRequired: return "export.permissionRequired"
        case .exportDisabled: return "export.exportDisabled"
        case .currentlySaving: return "export.currentlySaving"
        case .failedRetryable: return "export.failedRetryable"
        case .failedPermanent: return "export.failedPermanent"
        }
    }
}

/// Everything the decision needs, gathered by the caller so the evaluator itself
/// touches no storage and no framework.
public struct ExportEvaluationInput: Sendable {
    public var execution: WorkoutExecution
    public var sport: Sport
    public var isCompleted: Bool
    public var isExportEnabled: Bool
    public var isHealthDataAvailable: Bool
    public var writeAuthorization: HealthCapabilityState.Status
    /// A prior export attempt for this execution, if any.
    public var existingRecord: HealthExportRecord?
    /// Name of the owning source when the execution came from elsewhere.
    public var externalSourceName: String?

    public init(
        execution: WorkoutExecution,
        sport: Sport,
        isCompleted: Bool = true,
        isExportEnabled: Bool,
        isHealthDataAvailable: Bool = true,
        writeAuthorization: HealthCapabilityState.Status = .authorized,
        existingRecord: HealthExportRecord? = nil,
        externalSourceName: String? = nil
    ) {
        self.execution = execution
        self.sport = sport
        self.isCompleted = isCompleted
        self.isExportEnabled = isExportEnabled
        self.isHealthDataAvailable = isHealthDataAvailable
        self.writeAuthorization = writeAuthorization
        self.existingRecord = existingRecord
        self.externalSourceName = externalSourceName
    }
}

public enum ExportEligibilityEvaluator {

    /// Order matters, and is chosen so the *most informative* answer wins.
    ///
    /// Ownership and provenance are checked before permission or settings: if a
    /// workout came from Health, telling the athlete "turn on export" would be
    /// misleading, because turning it on still would not — and must not — export
    /// it. Structural facts first, then preferences.
    public static func evaluate(_ input: ExportEvaluationInput) -> ExportEligibility {

        // 1. Structural: is this even a completed session with usable dates?
        guard input.isCompleted else {
            return .missingRequiredData(reason: .notCompleted)
        }
        if input.execution.durationSeconds == 0 {
            return .missingRequiredData(reason: .zeroDuration)
        }
        if input.execution.durationSeconds < 0 {
            return .missingRequiredData(reason: .negativeDuration)
        }
        if input.execution.start == .distantPast {
            return .missingRequiredData(reason: .missingStart)
        }

        // 2. Provenance: never write back something we did not create.
        switch input.execution.source {
        case .healthKit:
            return .importedFromHealthKit
        case .appleWatch, .external:
            // The Watch already saved this to HealthKit itself; exporting again
            // is the canonical duplicate pathway (§3).
            return .externallyOwned(sourceName: input.externalSourceName)
        case .manual, .appTimer:
            break
        }

        // 3. Already exported.
        if let providerID = input.execution.exportedProviderID {
            return .alreadyExported(providerWorkoutID: providerID)
        }
        if let record = input.existingRecord {
            switch record.status {
            case .saved:
                if let id = record.providerWorkoutID {
                    return .alreadyExported(providerWorkoutID: id)
                }
            case .pending:
                return .currentlySaving
            case .failed:
                let category = record.lastFailure ?? .unknown
                return category.isRetryable
                    ? .failedRetryable(category: category)
                    : .failedPermanent(category: category)
            case .replacing:
                return .currentlySaving
            }
        }

        // 4. Representability. A brick or a race is genuinely multisport; filing
        //    it as a single activity would misrepresent the athlete's training,
        //    so Stage 3 refuses honestly rather than approximating.
        if input.sport == .brick || input.sport == .race {
            return .unsupportedMultisport(input.sport)
        }
        guard HealthActivityMapping.activityRawValue(for: input.sport) != nil else {
            return .unsupportedSport(input.sport)
        }

        // 5. Preferences and permission, last.
        guard input.isHealthDataAvailable else { return .permissionRequired }
        guard input.isExportEnabled else { return .exportDisabled }
        switch input.writeAuthorization {
        case .authorized: return .eligible
        case .notDetermined, .denied, .unknowable: return .permissionRequired
        }
    }
}

// MARK: - Export record

/// Durable state for one export attempt (§9).
///
/// Exists so a HealthKit save can never become an undetectable orphan: the
/// record is written *before* the save, so a crash between "HealthKit saved" and
/// "we stored the UUID" leaves a pending row that recovery can reconcile through
/// metadata.
public struct HealthExportRecord: Codable, Sendable, Hashable, Identifiable {

    public enum Status: String, Codable, Sendable, Hashable {
        case pending
        case saved
        case failed
        case replacing
    }

    public var id: UUID
    public var executionID: UUID
    public var scheduledWorkoutID: UUID?
    /// Stable across retries; derived from identity, never from title or date (§3).
    public var idempotencyKey: String
    public var status: Status
    /// The HealthKit object identifier, once known.
    public var providerWorkoutID: String?
    public var exportedAt: Date?
    public var exportVersion: Int
    public var lastFailure: ExportFailureCategory?
    public var attemptCount: Int
    /// True when Endurance created the Health record and may therefore replace
    /// or delete it. Never set for imported or externally recorded workouts (§7).
    public var isEnduranceOwned: Bool
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        executionID: UUID,
        scheduledWorkoutID: UUID? = nil,
        idempotencyKey: String,
        status: Status = .pending,
        providerWorkoutID: String? = nil,
        exportedAt: Date? = nil,
        exportVersion: Int = HealthExportRecord.currentVersion,
        lastFailure: ExportFailureCategory? = nil,
        attemptCount: Int = 0,
        isEnduranceOwned: Bool = true,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.executionID = executionID
        self.scheduledWorkoutID = scheduledWorkoutID
        self.idempotencyKey = idempotencyKey
        self.status = status
        self.providerWorkoutID = providerWorkoutID
        self.exportedAt = exportedAt
        self.exportVersion = exportVersion
        self.lastFailure = lastFailure
        self.attemptCount = attemptCount
        self.isEnduranceOwned = isEnduranceOwned
        self.updatedAt = updatedAt
    }

    /// Bump when the payload written to HealthKit changes shape.
    public static let currentVersion = 1

    /// A save that HealthKit may have completed but we never confirmed.
    public var isPotentialOrphan: Bool {
        status == .pending && providerWorkoutID == nil
    }

    /// The stable idempotency key for an execution (§3). Derived from identity
    /// only — a retitled or rescheduled workout keeps the same key, and two
    /// rapid taps therefore collide rather than duplicating.
    public static func idempotencyKey(for executionID: UUID) -> String {
        "endurance.export.\(executionID.uuidString)"
    }
}

/// Why an export attempt failed, in terms the UI can act on (§8).
public enum ExportFailureCategory: String, Codable, Sendable, Hashable, CaseIterable {
    case healthDataUnavailable
    case authorizationDenied
    case authorizationNotDetermined
    case unsupportedActivity
    case missingDates
    case invalidDuration
    case duplicatePrevented
    case saveFailed
    case deleteFailed
    case persistenceFailedAfterSave
    case replacementFailed
    case cancelled
    case unknown

    /// §8 classification.
    public enum Classification: String, Sendable, Hashable {
        case retryable
        case userActionRequired
        case permanentForWorkout
        case internalConsistencyFailure
    }

    public var classification: Classification {
        switch self {
        case .saveFailed, .deleteFailed, .replacementFailed, .unknown:
            return .retryable
        case .authorizationDenied, .authorizationNotDetermined, .healthDataUnavailable:
            return .userActionRequired
        case .unsupportedActivity, .missingDates, .invalidDuration, .duplicatePrevented, .cancelled:
            return .permanentForWorkout
        case .persistenceFailedAfterSave:
            // HealthKit has the workout but we lost the link. Recoverable, but
            // through reconciliation rather than a plain retry.
            return .internalConsistencyFailure
        }
    }

    public var isRetryable: Bool {
        switch classification {
        case .retryable, .internalConsistencyFailure: return true
        case .userActionRequired, .permanentForWorkout: return false
        }
    }

    public var localizationKey: String { "exportfail.\(rawValue)" }
}

/// The outcome of editing something already written to HealthKit (§6).
public enum ExportUpdateOutcome: String, Sendable, Hashable, Codable {
    /// Only local fields changed; HealthKit was not touched.
    case localOnlyUpdated
    /// A HealthKit-represented field changed; replacement is needed.
    case healthReplacementRequired
    case replacedSuccessfully
    case healthDeleteFailed
    /// The dangerous one: the old record is gone, the new one did not save.
    case healthSaveFailedAfterDelete
    case externallyOwnedCannotModify
    case userCancelled

    public var localizationKey: String { "exportupdate.\(rawValue)" }

    /// Whether the athlete must be asked before proceeding, because a visible
    /// Health record will be replaced or removed (§6).
    public var requiresConfirmation: Bool { self == .healthReplacementRequired }

    /// Whether local state needs recovery attention.
    public var needsRecovery: Bool { self == .healthSaveFailedAfterDelete }
}

/// Which local edits actually require rewriting the HealthKit record (§6).
///
/// Notes, RPE and soreness are Endurance-only concepts — HealthKit does not
/// represent them, so editing them must not churn the athlete's Health record.
public enum ExportRelevantField: String, Sendable, Hashable, CaseIterable {
    case duration
    case distance
    case sport
    case startDate

    public static let localOnly: Set<String> = ["notes", "perceivedExertion", "fatigue", "soreness"]

    /// True when a set of changed field names requires HealthKit replacement.
    public static func requiresReplacement(changedFields: Set<String>) -> Bool {
        let relevant = Set(ExportRelevantField.allCases.map(\.rawValue))
        return !changedFields.intersection(relevant).isEmpty
    }
}
