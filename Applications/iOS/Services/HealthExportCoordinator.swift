import Foundation
import SwiftData
import Observation
import EnduranceDomain
import EnduranceHealth

/// Abstracts the HealthKit write side so the whole export workflow — including
/// its failure paths — is testable without a device (§10).
protocol HealthExporting: Sendable {
    var isHealthDataAvailable: Bool { get }
    func requestWriteAuthorization() async throws -> [HealthCapabilityState]
    func writeAuthorizationStates() -> [HealthCapabilityState]
    func save(_ payload: HealthWorkoutExportPayload) async throws -> String
    func replace(providerWorkoutID: String, with payload: HealthWorkoutExportPayload) async throws -> String
    func delete(providerWorkoutID: String) async throws
    func findExportedWorkout(executionID: UUID) async throws -> String?
}

#if canImport(HealthKit)
extension HealthKitWorkoutExporter: HealthExporting {}
#endif

/// Reports health data as unavailable rather than faking success (§P, §T).
struct UnavailableHealthExporter: HealthExporting {
    var isHealthDataAvailable: Bool { false }
    func requestWriteAuthorization() async throws -> [HealthCapabilityState] {
        HealthCapabilityPlan.export.map {
            HealthCapabilityState(capability: $0.rawValue, access: .write, status: .denied)
        }
    }
    func writeAuthorizationStates() -> [HealthCapabilityState] {
        HealthCapabilityPlan.export.map {
            HealthCapabilityState(capability: $0.rawValue, access: .write, status: .denied)
        }
    }
    func save(_ payload: HealthWorkoutExportPayload) async throws -> String {
        throw HealthExportError.healthDataUnavailable
    }
    func replace(providerWorkoutID: String, with payload: HealthWorkoutExportPayload) async throws -> String {
        throw HealthExportError.healthDataUnavailable
    }
    func delete(providerWorkoutID: String) async throws {
        throw HealthExportError.healthDataUnavailable
    }
    func findExportedWorkout(executionID: UUID) async throws -> String? { nil }
}

/// Owns the export workflow (§3, §5, §9).
///
/// The ordering here is the whole design. A local completion is already durable
/// before this runs, and is never rolled back by a HealthKit failure — training
/// history belongs to the athlete, not to whether a system framework accepted a
/// write. Around that:
///
///   1. A pending record is persisted *before* the save, so a crash mid-save
///      leaves a discoverable row instead of an invisible orphan.
///   2. The idempotency key is derived from execution identity, so a double tap,
///      a retry, an App Intent and an in-app action all collide harmlessly.
///   3. The returned HealthKit id is persisted, which is what later lets the
///      anchored importer recognise the workout as ours and merge it.
@MainActor
@Observable
final class HealthExportCoordinator {

    private let exporter: any HealthExporting
    private let container: ModelContainer

    private(set) var writeAuthorization: [HealthCapabilityState] = []
    private(set) var isSaving = false
    /// Execution ids with a save currently in flight, so re-entry is impossible.
    private var inFlight: Set<UUID> = []

    /// Whether newly completed sessions are exported automatically (§5).
    var isAutoExportEnabled = false

    init(exporter: any HealthExporting, container: ModelContainer) {
        self.exporter = exporter
        self.container = container
    }

    private var context: ModelContext { container.mainContext }

    static func defaultExporter() -> any HealthExporting {
        #if canImport(HealthKit)
        return HealthKitWorkoutExporter()
        #else
        return UnavailableHealthExporter()
        #endif
    }

    // MARK: - Authorization

    func refreshAuthorization() {
        writeAuthorization = exporter.isHealthDataAvailable
            ? exporter.writeAuthorizationStates()
            : []
    }

    /// Ask for write access only once the athlete has enabled export (§4).
    func enableExport() async {
        guard exporter.isHealthDataAvailable else { return }
        do {
            writeAuthorization = try await exporter.requestWriteAuthorization()
            isAutoExportEnabled = writeStatus == .authorized
        } catch {
            writeAuthorization = exporter.writeAuthorizationStates()
        }
    }

    var writeStatus: HealthCapabilityState.Status {
        writeAuthorization.first { $0.capability == HealthCapability.workouts.rawValue }?.status
            ?? .notDetermined
    }

    // MARK: - Eligibility

    /// The state a view renders. Views never compute this themselves (§1).
    func eligibility(for execution: WorkoutExecution, sport: Sport, isCompleted: Bool = true) -> ExportEligibility {
        if inFlight.contains(execution.id) { return .currentlySaving }
        return ExportEligibilityEvaluator.evaluate(
            ExportEvaluationInput(
                execution: execution,
                sport: sport,
                isCompleted: isCompleted,
                isExportEnabled: isAutoExportEnabled,
                isHealthDataAvailable: exporter.isHealthDataAvailable,
                writeAuthorization: writeStatus,
                existingRecord: record(for: execution.id)))
    }

    // MARK: - Export

    @discardableResult
    func export(execution: WorkoutExecution, sport: Sport) async -> ExportEligibility {
        // Re-entrancy guard: rapid taps, an intent and a UI action, or a retry
        // arriving while the first is still running (§3).
        guard !inFlight.contains(execution.id) else { return .currentlySaving }

        let decision = eligibility(for: execution, sport: sport)
        guard decision.canExportNow else { return decision }

        let payload: HealthWorkoutExportPayload
        do {
            payload = try HealthExportPayloadBuilder.build(
                for: ExportEvaluationInput(
                    execution: execution,
                    sport: sport,
                    isExportEnabled: isAutoExportEnabled,
                    isHealthDataAvailable: exporter.isHealthDataAvailable,
                    writeAuthorization: writeStatus,
                    existingRecord: record(for: execution.id)))
        } catch {
            markFailure(execution: execution, category: .unsupportedActivity)
            return eligibility(for: execution, sport: sport)
        }


        inFlight.insert(execution.id)
        isSaving = true
        // Safety net for any future early exit; `remove` is idempotent so it is
        // harmless alongside the explicit clear below.
        defer {
            inFlight.remove(execution.id)
            isSaving = !inFlight.isEmpty
        }

        // Persist intent BEFORE the save — this is what makes an interrupted
        // save recoverable rather than invisible (§9).
        beginRecord(for: execution)

        do {
            let providerID = try await exporter.save(payload)
            completeRecord(execution: execution, providerWorkoutID: providerID)
        } catch let error as HealthExportError {
            markFailure(execution: execution, category: error.category)
        } catch {
            markFailure(execution: execution, category: .saveFailed)
        }

        // Clear in-flight BEFORE computing the reported state. `defer` runs
        // after the return value is evaluated, so relying on it here reported
        // "currently saving" for a save that had already finished.
        inFlight.remove(execution.id)
        isSaving = !inFlight.isEmpty
        return eligibility(for: execution, sport: sport)
    }

    /// Called after a completion is already persisted locally (§5).
    func exportIfAutomatic(execution: WorkoutExecution, sport: Sport) async {
        guard isAutoExportEnabled else { return }
        await export(execution: execution, sport: sport)
    }

    // MARK: - Orphan recovery (§9)

    /// Reconnect exports that HealthKit accepted but we never linked.
    ///
    /// Runs on launch. Without it, a crash between save and persistence would
    /// leave a workout in Health that Endurance can neither show nor avoid
    /// re-exporting — the "undetectable orphan" §9 forbids.
    func recoverOrphanedExports() async {
        let candidates = ((try? context.fetch(FetchDescriptor<SDHealthExportRecord>())) ?? [])
            .compactMap { try? $0.toDomain() }
            .filter(\.isPotentialOrphan)

        for orphan in candidates {
            guard let providerID = try? await exporter.findExportedWorkout(
                executionID: orphan.executionID) else { continue }
            var recovered = orphan
            recovered.status = .saved
            recovered.providerWorkoutID = providerID
            recovered.exportedAt = Date()
            recovered.lastFailure = nil
            recovered.updatedAt = Date()
            persist(recovered)
            linkExecution(orphan.executionID, providerWorkoutID: providerID)
        }
        try? context.save()
    }

    // MARK: - Deletion (§7)

    /// Delete only Endurance-created Health records. Refuses anything else.
    @discardableResult
    func deleteExportedWorkout(executionID: UUID) async -> Result<Void, HealthOwnership.DeletionRefusal> {
        let stored = record(for: executionID)
        switch HealthOwnership.mayDelete(stored) {
        case .failure(let refusal):
            return .failure(refusal)
        case .success(let providerID):
            do {
                try await exporter.delete(providerWorkoutID: providerID)
                if var updated = stored {
                    updated.status = .failed
                    updated.providerWorkoutID = nil
                    updated.lastFailure = nil
                    updated.updatedAt = Date()
                    persist(updated)
                }
                linkExecution(executionID, providerWorkoutID: nil)
                try? context.save()
                return .success(())
            } catch {
                return .failure(.noProviderReference)
            }
        }
    }

    /// Every Endurance-owned Health record, for the explicit bulk-delete flow.
    func enduranceOwnedExports() -> [HealthExportRecord] {
        ((try? context.fetch(FetchDescriptor<SDHealthExportRecord>())) ?? [])
            .compactMap { try? $0.toDomain() }
            .filter { $0.isEnduranceOwned && $0.providerWorkoutID != nil && $0.status == .saved }
    }

    /// Remove Endurance's local connection records without touching Health (§7).
    func removeLocalConnectionRecords() {
        do {
            try context.delete(model: SDHealthExportRecord.self)
            try context.save()
        } catch {
            AppLog.persistence.error("Removing export records failed: \(error)")
        }
    }

    // MARK: - Record helpers

    func record(for executionID: UUID) -> HealthExportRecord? {
        ((try? context.fetch(FetchDescriptor<SDHealthExportRecord>())) ?? [])
            .first { $0.executionID == executionID }
            .flatMap { try? $0.toDomain() }
    }

    private func beginRecord(for execution: WorkoutExecution) {
        var record = self.record(for: execution.id) ?? HealthExportRecord(
            executionID: execution.id,
            scheduledWorkoutID: execution.scheduledWorkoutID,
            idempotencyKey: HealthExportRecord.idempotencyKey(for: execution.id))
        record.status = .pending
        record.attemptCount += 1
        record.updatedAt = Date()
        persist(record)
        try? context.save()
    }

    private func completeRecord(execution: WorkoutExecution, providerWorkoutID: String) {
        var record = self.record(for: execution.id) ?? HealthExportRecord(
            executionID: execution.id,
            idempotencyKey: HealthExportRecord.idempotencyKey(for: execution.id))
        record.status = .saved
        record.providerWorkoutID = providerWorkoutID
        record.exportedAt = Date()
        record.lastFailure = nil
        record.isEnduranceOwned = true
        record.updatedAt = Date()
        persist(record)
        linkExecution(execution.id, providerWorkoutID: providerWorkoutID)

        do {
            try context.save()
        } catch {
            // HealthKit has the workout but we could not store the link. Leave
            // the record pending so `recoverOrphanedExports` finds it via
            // metadata — never let this become a silent orphan (§9).
            AppLog.persistence.error("Export link persistence failed; orphan recovery will reconcile.")
            markFailure(execution: execution, category: .persistenceFailedAfterSave)
        }
    }

    private func markFailure(execution: WorkoutExecution, category: ExportFailureCategory) {
        var record = self.record(for: execution.id) ?? HealthExportRecord(
            executionID: execution.id,
            idempotencyKey: HealthExportRecord.idempotencyKey(for: execution.id))
        record.status = .failed
        record.lastFailure = category
        record.updatedAt = Date()
        persist(record)
        try? context.save()
        // Stable code only — never a HealthKit UUID or a health value (§Q).
        AppLog.app.error("Health export failed: \(category.rawValue, privacy: .public)")
    }

    private func persist(_ record: HealthExportRecord) {
        let rows = (try? context.fetch(FetchDescriptor<SDHealthExportRecord>())) ?? []
        if let existing = rows.first(where: { $0.executionID == record.executionID }) {
            try? existing.update(record)
        } else if let inserted = try? SDHealthExportRecord(domain: record) {
            context.insert(inserted)
        }
    }

    /// Mirror the provider reference onto the execution, so eligibility and the
    /// importer both see it without a second lookup.
    private func linkExecution(_ executionID: UUID, providerWorkoutID: String?) {
        let rows = (try? context.fetch(FetchDescriptor<SDWorkoutExecution>())) ?? []
        guard let row = rows.first(where: { $0.executionID == executionID }),
              var domain = try? row.toDomain() else { return }
        domain.exportedProviderID = providerWorkoutID
        try? row.update(domain)
    }
}
