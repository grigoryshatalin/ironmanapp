import Foundation
import SwiftData
import Observation
import EnduranceDomain
import EnduranceHealth

/// Orchestrates HealthKit import for the app (§D, §E, §O).
///
/// The importer is injected as a protocol, so this whole flow — authorization
/// state, incremental import, reconciliation, matching, and the resulting inbox
/// — is exercised in tests with a deterministic fake and no device, entitlement,
/// or permission prompt. Production code never fakes framework success (§T).
@MainActor
@Observable
final class HealthCoordinator {

    /// One activity awaiting the athlete's decision.
    struct InboxItem: Identifiable, Equatable {
        var id: String { summary.idempotencyKey }
        var summary: ExternalWorkoutSummary
        var match: WorkoutMatcher.Match
        /// The planned session the suggestion points at, when there is one.
        var suggestion: ScheduledWorkout?
    }

    /// What the Health section shows about its own state (§M).
    enum ConnectionState: Equatable {
        case unavailable          // device cannot provide health data at all
        case notConnected         // never asked
        case connected            // asked, and import is on
        case importPaused         // asked, but the athlete turned import off
    }

    private let importer: any HealthWorkoutImporting
    private let container: ModelContainer
    private let reconciler: ImportReconciler
    private let matcher = WorkoutMatcher()
    private let workoutStore: WorkoutStore

    private(set) var connection: ConnectionState = .notConnected
    private(set) var capabilityStates: [HealthCapabilityState] = []
    private(set) var inbox: [InboxItem] = []
    private(set) var lastSuccessfulImport: Date?
    private(set) var lastErrorCode: String?
    private(set) var isImporting = false

    /// Athlete preferences. Import and export are independently opt-in (§F).
    var isImportEnabled = false
    var isExportEnabled = false

    init(
        importer: any HealthWorkoutImporting,
        container: ModelContainer,
        workoutStore: WorkoutStore,
        appBundleIdentifier: String = AppConfig.bundleIdentifier
    ) {
        self.importer = importer
        self.container = container
        self.workoutStore = workoutStore
        self.reconciler = ImportReconciler(appBundleIdentifier: appBundleIdentifier)
    }

    private var context: ModelContext { container.mainContext }

    // MARK: - Authorization

    func refreshConnectionState() async {
        guard importer.isHealthDataAvailable else {
            connection = .unavailable
            return
        }
        capabilityStates = await importer.authorizationStates(for: HealthCapabilityPlan.coreImport)
        let everAsked = capabilityStates.contains { $0.status != .notDetermined }
        connection = everAsked ? (isImportEnabled ? .connected : .importPaused) : .notConnected
        loadPersistedCursorState()
    }

    /// Request only the capabilities the import feature actually uses (§C).
    func connect() async {
        guard importer.isHealthDataAvailable else {
            connection = .unavailable
            return
        }
        do {
            capabilityStates = try await importer.requestAuthorization(for: HealthCapabilityPlan.coreImport)
            isImportEnabled = true
            connection = .connected
            await runImport()
        } catch {
            record(error: .healthImport, code: "authorization_failed")
        }
    }

    /// Disconnecting stops import and clears Endurance's own integration
    /// records. It never deletes training history, and never touches workouts
    /// owned by other apps (§F, §Q).
    func disconnect() {
        isImportEnabled = false
        isExportEnabled = false
        connection = .importPaused
        inbox = []
        do {
            try context.delete(model: SDExternalWorkoutRecord.self)
            try context.delete(model: SDHealthImportCursor.self)
            try context.delete(model: SDWorkoutMatchDecision.self)
            try context.save()
        } catch {
            AppLog.persistence.error("Health disconnect cleanup failed: \(error)")
        }
    }

    // MARK: - Import

    func runImport() async {
        guard isImportEnabled, !isImporting else { return }
        isImporting = true
        defer { isImporting = false }

        let cursor = persistedCursor()
        do {
            let batch = try await importer.importWorkouts(since: cursor)
            let known = knownState()
            let outcome = reconciler.reconcile(batch, known: known)

            try apply(outcome, cursor: batch.updatedCursor)
            rebuildInbox()
            lastSuccessfulImport = batch.updatedCursor.lastSuccessfulImport
            lastErrorCode = nil
        } catch let error as HealthImportError {
            record(error: .healthImport, code: error.logCode)
        } catch {
            record(error: .healthImport, code: "health.import_failed")
        }
    }

    private func apply(_ outcome: ImportReconciler.Outcome, cursor: ImportCursor) throws {
        for summary in outcome.newSummaries {
            context.insert(try SDExternalWorkoutRecord(domain: summary))
        }
        for summary in outcome.updatedSummaries {
            if let record = try fetchRecord(key: summary.idempotencyKey) {
                try record.update(summary)
            }
        }
        for key in outcome.deletedKeys {
            if let record = try fetchRecord(key: key) {
                var domain = try record.toDomain()
                domain.isDeletedAtSource = true
                try record.update(domain)
            }
        }
        persist(cursor: cursor)
        try context.save()
    }

    // MARK: - Inbox and decisions

    /// Rebuild the review list: unmatched activities, scored against the plan,
    /// minus anything the athlete has already decided about (§E).
    private func rebuildInbox() {
        let decided = decidedKeys()
        let executions = allExecutions()
        let executedIDs = Set(executions.compactMap(\.scheduledWorkoutID))
        let links = executionLinks(executions)
        let importedKeys = Set(executions.flatMap(\.externalKeys))

        let records = (try? context.fetch(FetchDescriptor<SDExternalWorkoutRecord>())) ?? []
        let summaries = records.compactMap { try? $0.toDomain() }
            .filter { !$0.isDeletedAtSource && !decided.contains($0.idempotencyKey) }

        let planned = workoutStore.allWorkouts

        inbox = summaries.compactMap { summary in
            // Only consider sessions within a day of the activity — the matcher
            // enforces its own window, this just avoids scoring 382 candidates.
            let nearby = planned.filter {
                abs($0.plannedStart.timeIntervalSince(summary.start)) <= 24 * 60 * 60
            }
            let match = matcher.match(
                summary,
                against: nearby,
                existingLinks: links,
                executedWorkoutIDs: executedIDs,
                alreadyImportedKeys: importedKeys)

            guard match.confidence != .duplicate else { return nil }
            let suggestion = match.scheduledWorkoutID.flatMap { id in planned.first { $0.id == id } }
            return InboxItem(summary: summary, match: match, suggestion: suggestion)
        }
        .sorted { $0.summary.start > $1.summary.start }
    }

    /// Attach an imported activity to a planned session.
    func confirm(_ item: InboxItem, to scheduledWorkoutID: UUID) {
        let execution = WorkoutExecution(
            scheduledWorkoutID: scheduledWorkoutID,
            source: .healthKit,
            start: item.summary.start,
            durationSeconds: item.summary.durationSeconds,
            distanceMeters: item.summary.distanceMeters,
            averageHeartRate: item.summary.averageHeartRate,
            activeEnergyKilocalories: item.summary.activeEnergyKilocalories,
            externalKeys: [item.summary.idempotencyKey])

        do {
            // Guard the merge path even here: a confirmation racing an import
            // must not create a twin (§O).
            let merger = ExecutionMerger()
            switch merger.resolve(
                incoming: execution,
                externalKey: item.summary.idempotencyKey,
                against: allExecutions()
            ) {
            case .insert(let new):
                context.insert(try SDWorkoutExecution(domain: new))
            case .attach(let existingID, let key):
                try attach(key: key, toExecution: existingID)
            case .ignore:
                break
            }

            // Reflect it on the plan itself.
            try workoutStore.complete(
                scheduledWorkoutID,
                completion: WorkoutCompletion(
                    completedAt: item.summary.end,
                    actualDurationMinutes: item.summary.durationMinutes,
                    actualDistanceMeters: item.summary.distanceMeters,
                    averageHeartRate: item.summary.averageHeartRate,
                    source: .healthKit))

            try record(decision: .confirmed, for: item, scheduledWorkoutID: scheduledWorkoutID)
        } catch {
            AppLog.persistence.error("Confirming health match failed: \(error)")
        }
    }

    func reject(_ item: InboxItem) {
        try? record(decision: .rejected, for: item, scheduledWorkoutID: nil)
    }

    func keepAsUnplanned(_ item: InboxItem) {
        do {
            let execution = WorkoutExecution(
                scheduledWorkoutID: nil,
                source: .healthKit,
                start: item.summary.start,
                durationSeconds: item.summary.durationSeconds,
                distanceMeters: item.summary.distanceMeters,
                externalKeys: [item.summary.idempotencyKey])
            context.insert(try SDWorkoutExecution(domain: execution))
            try record(decision: .keptAsUnplanned, for: item, scheduledWorkoutID: nil)
        } catch {
            AppLog.persistence.error("Keeping unplanned activity failed: \(error)")
        }
    }

    /// Undo restores the suggestion so the athlete can choose again (§E).
    func undo(_ item: InboxItem) {
        do {
            let descriptor = FetchDescriptor<SDWorkoutMatchDecision>()
            for decision in try context.fetch(descriptor)
            where decision.idempotencyKey == item.summary.idempotencyKey {
                context.delete(decision)
            }
            try context.save()
            rebuildInbox()
        } catch {
            AppLog.persistence.error("Undo failed: \(error)")
        }
    }

    // MARK: - Persistence helpers

    private func record(
        decision outcome: WorkoutMatchDecision.Outcome,
        for item: InboxItem,
        scheduledWorkoutID: UUID?
    ) throws {
        let decision = WorkoutMatchDecision(
            idempotencyKey: item.summary.idempotencyKey,
            scheduledWorkoutID: scheduledWorkoutID,
            outcome: outcome,
            suggestedConfidence: item.match.confidence)
        context.insert(try SDWorkoutMatchDecision(domain: decision))
        try context.save()
        rebuildInbox()
    }

    private func attach(key: String?, toExecution id: UUID) throws {
        guard let key else { return }
        let records = try context.fetch(FetchDescriptor<SDWorkoutExecution>())
        guard let record = records.first(where: { $0.executionID == id }) else { return }
        var domain = try record.toDomain()
        domain.externalKeys.insert(key)
        try record.update(domain)
    }

    private func fetchRecord(key: String) throws -> SDExternalWorkoutRecord? {
        try context.fetch(FetchDescriptor<SDExternalWorkoutRecord>())
            .first { $0.idempotencyKey == key }
    }

    /// Everything the reconciler needs to recognise a re-delivery: activities
    /// already stored, and external keys already attached to an execution.
    private func knownState() -> ImportReconciler.KnownState {
        let records = (try? context.fetch(FetchDescriptor<SDExternalWorkoutRecord>())) ?? []
        var summaries: [String: ExternalWorkoutSummary] = [:]
        for record in records {
            if let domain = try? record.toDomain() {
                summaries[domain.idempotencyKey] = domain
            }
        }
        return ImportReconciler.KnownState(
            summaries: summaries,
            executionKeys: Set(allExecutions().flatMap(\.externalKeys)))
    }

    private func allExecutions() -> [WorkoutExecution] {
        ((try? context.fetch(FetchDescriptor<SDWorkoutExecution>())) ?? [])
            .compactMap { try? $0.toDomain() }
    }

    private func executionLinks(_ executions: [WorkoutExecution]) -> [String: UUID] {
        var links: [String: UUID] = [:]
        for execution in executions {
            guard let sessionID = execution.scheduledWorkoutID else { continue }
            for key in execution.externalKeys { links[key] = sessionID }
        }
        return links
    }

    private func decidedKeys() -> Set<String> {
        let decisions = ((try? context.fetch(FetchDescriptor<SDWorkoutMatchDecision>())) ?? [])
            .compactMap { try? $0.toDomain() }
        return Set(decisions.filter(\.suppressesFutureSuggestions).map(\.idempotencyKey))
    }

    private func persistedCursor() -> ImportCursor {
        let rows = (try? context.fetch(FetchDescriptor<SDHealthImportCursor>())) ?? []
        return rows.first { $0.providerRaw == WorkoutProvider.healthKit.rawValue }?.toDomain()
            ?? ImportCursor(provider: .healthKit)
    }

    private func persist(cursor: ImportCursor) {
        let rows = (try? context.fetch(FetchDescriptor<SDHealthImportCursor>())) ?? []
        if let existing = rows.first(where: { $0.providerRaw == cursor.provider.rawValue }) {
            existing.update(cursor)
        } else {
            context.insert(SDHealthImportCursor(domain: cursor))
        }
    }

    private func loadPersistedCursorState() {
        let cursor = persistedCursor()
        lastSuccessfulImport = cursor.lastSuccessfulImport
        lastErrorCode = cursor.lastErrorDescription
        rebuildInbox()
    }

    /// Errors are logged as stable codes only — never raw framework text, and
    /// never anything derived from health values (§Q).
    private func record(error area: IntegrationErrorRecord.Area, code: String) {
        lastErrorCode = code
        AppLog.app.error("Integration error \(area.rawValue, privacy: .public): \(code, privacy: .public)")
        context.insert(SDIntegrationErrorRecord(
            domain: IntegrationErrorRecord(area: area, code: code, isRecoverable: true)))
        try? context.save()
    }
}

// MARK: - Default wiring

extension HealthCoordinator {
    /// The real adapter on platforms that have HealthKit; a stub that reports
    /// "unavailable" elsewhere. The stub is *not* a fake success — it makes the
    /// UI show the honest unavailable state (§P).
    static func defaultImporter() -> any HealthWorkoutImporting {
        #if canImport(HealthKit)
        return HealthKitWorkoutImporter(appBundleIdentifier: AppConfig.bundleIdentifier)
        #else
        return UnavailableHealthImporter()
        #endif
    }
}

/// Reports health data as unavailable. Used where HealthKit does not exist, so
/// the app degrades to a truthful state rather than pretending (§P).
struct UnavailableHealthImporter: HealthWorkoutImporting {
    var isHealthDataAvailable: Bool { false }

    func requestAuthorization(for capabilities: [HealthCapability]) async throws -> [HealthCapabilityState] {
        capabilities.map { HealthCapabilityState(capability: $0.rawValue, access: .read, status: .denied) }
    }

    func authorizationStates(for capabilities: [HealthCapability]) async -> [HealthCapabilityState] {
        capabilities.map { HealthCapabilityState(capability: $0.rawValue, access: .read, status: .denied) }
    }

    func importWorkouts(since cursor: ImportCursor) async throws -> HealthImportBatch {
        throw HealthImportError.healthDataUnavailable
    }
}
