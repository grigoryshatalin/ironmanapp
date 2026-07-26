import Foundation
import SwiftData
import EnduranceDomain
import EnduranceHealth

/// Release 2 persistence (§N).
///
/// Two rules carried over from Release 1:
///   * Query fields are stored as columns; the full domain value type is kept as
///     an encoded payload, so the domain stays the single source of truth and
///     the two cannot drift.
///   * High-frequency live samples are **not** duplicated here — HealthKit is
///     the authoritative store for those. What is persisted is only what offline
///     display, matching, progress, conflict resolution, export and interruption
///     recovery genuinely need.
///
/// CloudKit forward-compatibility (§N): every property below is either optional
/// or has a default, and none carries a `.unique` constraint, because CloudKit
/// supports neither. See `DATA_SCHEMA.md` — the two Release 1 models still use
/// `.unique`, which must be dropped before CloudKit can be enabled.

// MARK: - External activity

/// One activity observed from a provider. Uniqueness is enforced in code via
/// `idempotencyKey` rather than a `.unique` attribute, to stay CloudKit-ready.
@Model
final class SDExternalWorkoutRecord {
    var idempotencyKey: String = ""
    var providerRaw: String = ""
    var providerWorkoutID: String = ""
    var start: Date = Date.distantPast
    var sportRaw: String = ""
    var isDeletedAtSource: Bool = false
    /// Set once the activity has been attached to a planned session.
    var matchedScheduledWorkoutID: UUID?
    var executionID: UUID?
    var payload: Data = Data()

    init(domain: ExternalWorkoutSummary) throws {
        self.idempotencyKey = domain.idempotencyKey
        self.providerRaw = domain.provider.rawValue
        self.providerWorkoutID = domain.providerWorkoutID
        self.start = domain.start
        self.sportRaw = domain.sport.rawValue
        self.isDeletedAtSource = domain.isDeletedAtSource
        self.payload = try SDCoders.encoder.encode(domain)
    }

    func toDomain() throws -> ExternalWorkoutSummary {
        try SDCoders.decoder.decode(ExternalWorkoutSummary.self, from: payload)
    }

    func update(_ domain: ExternalWorkoutSummary) throws {
        start = domain.start
        sportRaw = domain.sport.rawValue
        isDeletedAtSource = domain.isDeletedAtSource
        payload = try SDCoders.encoder.encode(domain)
    }
}

// MARK: - Execution

/// A performance of a session, however it was observed.
@Model
final class SDWorkoutExecution {
    var executionID: UUID = UUID()
    var scheduledWorkoutID: UUID?
    var start: Date = Date.distantPast
    var sourceRaw: String = ""
    var exportedProviderID: String?
    var payload: Data = Data()

    init(domain: WorkoutExecution) throws {
        self.executionID = domain.id
        self.scheduledWorkoutID = domain.scheduledWorkoutID
        self.start = domain.start
        self.sourceRaw = domain.source.rawValue
        self.exportedProviderID = domain.exportedProviderID
        self.payload = try SDCoders.encoder.encode(domain)
    }

    func toDomain() throws -> WorkoutExecution {
        try SDCoders.decoder.decode(WorkoutExecution.self, from: payload)
    }

    func update(_ domain: WorkoutExecution) throws {
        scheduledWorkoutID = domain.scheduledWorkoutID
        start = domain.start
        sourceRaw = domain.source.rawValue
        exportedProviderID = domain.exportedProviderID
        payload = try SDCoders.encoder.encode(domain)
    }
}

// MARK: - Match decisions

/// Persisted so a rejected suggestion never returns (§E).
@Model
final class SDWorkoutMatchDecision {
    var idempotencyKey: String = ""
    var scheduledWorkoutID: UUID?
    var outcomeRaw: String = ""
    var decidedAt: Date = Date.distantPast
    var payload: Data = Data()

    init(domain: WorkoutMatchDecision) throws {
        self.idempotencyKey = domain.idempotencyKey
        self.scheduledWorkoutID = domain.scheduledWorkoutID
        self.outcomeRaw = domain.outcome.rawValue
        self.decidedAt = domain.decidedAt
        self.payload = try SDCoders.encoder.encode(domain)
    }

    func toDomain() throws -> WorkoutMatchDecision {
        try SDCoders.decoder.decode(WorkoutMatchDecision.self, from: payload)
    }
}

// MARK: - Import cursor

/// One row per provider, holding the opaque incremental-import anchor (§D).
@Model
final class SDHealthImportCursor {
    var providerRaw: String = ""
    var anchorData: Data?
    var lastSuccessfulImport: Date?
    var lastAttempt: Date?
    var lastErrorDescription: String?

    init(domain: ImportCursor) {
        self.providerRaw = domain.provider.rawValue
        self.anchorData = domain.anchorData
        self.lastSuccessfulImport = domain.lastSuccessfulImport
        self.lastAttempt = domain.lastAttempt
        self.lastErrorDescription = domain.lastErrorDescription
    }

    func toDomain() -> ImportCursor {
        ImportCursor(
            provider: WorkoutProvider(rawValue: providerRaw) ?? .healthKit,
            anchorData: anchorData,
            lastSuccessfulImport: lastSuccessfulImport,
            lastAttempt: lastAttempt,
            lastErrorDescription: lastErrorDescription)
    }

    func update(_ domain: ImportCursor) {
        anchorData = domain.anchorData
        lastSuccessfulImport = domain.lastSuccessfulImport
        lastAttempt = domain.lastAttempt
        lastErrorDescription = domain.lastErrorDescription
    }
}

// MARK: - Health authorization

/// Per-capability, per-access authorization. Never collapsed into one boolean (§C).
@Model
final class SDHealthAuthorizationState {
    var capability: String = ""
    var accessRaw: String = ""
    var statusRaw: String = ""
    var updatedAt: Date = Date.distantPast

    init(domain: HealthCapabilityState, updatedAt: Date = Date()) {
        self.capability = domain.capability
        self.accessRaw = domain.access.rawValue
        self.statusRaw = domain.status.rawValue
        self.updatedAt = updatedAt
    }

    func toDomain() -> HealthCapabilityState? {
        guard let access = HealthCapabilityState.Access(rawValue: accessRaw),
              let status = HealthCapabilityState.Status(rawValue: statusRaw) else { return nil }
        return HealthCapabilityState(capability: capability, access: access, status: status)
    }
}

// MARK: - WorkoutKit schedule

@Model
final class SDWorkoutKitScheduleRecord {
    var scheduledWorkoutID: UUID = UUID()
    var schedulingIdentifier: String = ""
    var conversionKindRaw: String = ""
    var conversionVersion: Int = 0
    var plannedDate: Date = Date.distantPast
    var isStale: Bool = false
    var payload: Data = Data()

    init(domain: WorkoutKitScheduleRecord) throws {
        self.scheduledWorkoutID = domain.scheduledWorkoutID
        self.schedulingIdentifier = domain.schedulingIdentifier
        self.conversionKindRaw = domain.conversionKind.rawValue
        self.conversionVersion = domain.conversionVersion
        self.plannedDate = domain.plannedDate
        self.isStale = domain.isStale
        self.payload = try SDCoders.encoder.encode(domain)
    }

    func toDomain() throws -> WorkoutKitScheduleRecord {
        try SDCoders.decoder.decode(WorkoutKitScheduleRecord.self, from: payload)
    }
}

// MARK: - Watch sync

/// Durable outbound/inbound queue entry, so a transfer survives termination and
/// a repeated delivery cannot duplicate a completion (§H, §O).
@Model
final class SDWatchSyncRecord {
    var executionID: UUID = UUID()
    var directionRaw: String = ""
    var enqueuedAt: Date = Date.distantPast
    var acknowledgedAt: Date?
    var attemptCount: Int = 0
    var payload: Data = Data()

    init(executionID: UUID, direction: String, payload: Data, enqueuedAt: Date = Date()) {
        self.executionID = executionID
        self.directionRaw = direction
        self.payload = payload
        self.enqueuedAt = enqueuedAt
    }

    var isAcknowledged: Bool { acknowledgedAt != nil }
}

// MARK: - Active workout recovery

/// Single live-session record, so an interrupted workout can be resumed (§G).
@Model
final class SDActiveWorkoutRecovery {
    var executionID: UUID = UUID()
    var stateRaw: String = ""
    var updatedAt: Date = Date.distantPast
    var payload: Data = Data()

    init(domain: ActiveWorkoutRecovery) throws {
        self.executionID = domain.executionID
        self.stateRaw = domain.state.rawValue
        self.updatedAt = domain.updatedAt
        self.payload = try SDCoders.encoder.encode(domain)
    }

    func toDomain() throws -> ActiveWorkoutRecovery {
        try SDCoders.decoder.decode(ActiveWorkoutRecovery.self, from: payload)
    }

    func update(_ domain: ActiveWorkoutRecovery) throws {
        stateRaw = domain.state.rawValue
        updatedAt = domain.updatedAt
        payload = try SDCoders.encoder.encode(domain)
    }
}

// MARK: - Integration errors

@Model
final class SDIntegrationErrorRecord {
    var areaRaw: String = ""
    var code: String = ""
    var occurredAt: Date = Date.distantPast
    var isRecoverable: Bool = false

    init(domain: IntegrationErrorRecord) {
        self.areaRaw = domain.area.rawValue
        self.code = domain.code
        self.occurredAt = domain.occurredAt
        self.isRecoverable = domain.isRecoverable
    }

    func toDomain() -> IntegrationErrorRecord? {
        guard let area = IntegrationErrorRecord.Area(rawValue: areaRaw) else { return nil }
        return IntegrationErrorRecord(
            area: area, occurredAt: occurredAt, code: code, isRecoverable: isRecoverable)
    }
}

// MARK: - Health export

/// Durable state for one export attempt (§9).
///
/// Written *before* the HealthKit save, so a crash between "HealthKit saved" and
/// "we stored the identifier" leaves a discoverable pending row rather than an
/// invisible orphan.
@Model
final class SDHealthExportRecord {
    var executionID: UUID = UUID()
    var scheduledWorkoutID: UUID?
    var idempotencyKey: String = ""
    var statusRaw: String = ""
    var providerWorkoutID: String?
    var exportedAt: Date?
    var lastFailureRaw: String?
    var attemptCount: Int = 0
    var isEnduranceOwned: Bool = true
    var updatedAt: Date = Date.distantPast
    var payload: Data = Data()

    init(domain: HealthExportRecord) throws {
        self.executionID = domain.executionID
        self.scheduledWorkoutID = domain.scheduledWorkoutID
        self.idempotencyKey = domain.idempotencyKey
        self.statusRaw = domain.status.rawValue
        self.providerWorkoutID = domain.providerWorkoutID
        self.exportedAt = domain.exportedAt
        self.lastFailureRaw = domain.lastFailure?.rawValue
        self.attemptCount = domain.attemptCount
        self.isEnduranceOwned = domain.isEnduranceOwned
        self.updatedAt = domain.updatedAt
        self.payload = try SDCoders.encoder.encode(domain)
    }

    func toDomain() throws -> HealthExportRecord {
        try SDCoders.decoder.decode(HealthExportRecord.self, from: payload)
    }

    func update(_ domain: HealthExportRecord) throws {
        statusRaw = domain.status.rawValue
        providerWorkoutID = domain.providerWorkoutID
        exportedAt = domain.exportedAt
        lastFailureRaw = domain.lastFailure?.rawValue
        attemptCount = domain.attemptCount
        isEnduranceOwned = domain.isEnduranceOwned
        updatedAt = domain.updatedAt
        payload = try SDCoders.encoder.encode(domain)
    }
}

// MARK: - Shared coders

/// Shared JSON coders for the payload columns. Kept in one place so encoding
/// settings cannot diverge between entities and silently break decoding.
enum SDCoders {
    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
