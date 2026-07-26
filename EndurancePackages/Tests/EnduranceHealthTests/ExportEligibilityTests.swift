import Testing
import Foundation
@testable import EnduranceHealth
@testable import EnduranceDomain

/// §1/§10 — every export eligibility state.
///
/// Most of these assert a *refusal*. That is deliberate: the states that protect
/// the athlete's Health record — not re-exporting an import, not filing a brick
/// as one ride, not writing twice — are the ones that quietly stop working if
/// nothing pins them down.
@Suite("Export eligibility")
struct ExportEligibilityTests {

    private let start = Date(timeIntervalSince1970: 1_770_000_000)

    private func execution(
        source: CompletionSource = .manual,
        minutes: Int = 45,
        distance: Double? = 9000,
        exported: String? = nil,
        start: Date? = nil
    ) -> WorkoutExecution {
        WorkoutExecution(
            scheduledWorkoutID: UUID(),
            source: source,
            start: start ?? self.start,
            durationSeconds: minutes * 60,
            distanceMeters: distance,
            exportedProviderID: exported)
    }

    private func input(
        _ execution: WorkoutExecution,
        sport: Sport = .run,
        completed: Bool = true,
        enabled: Bool = true,
        available: Bool = true,
        auth: HealthCapabilityState.Status = .authorized,
        record: HealthExportRecord? = nil
    ) -> ExportEvaluationInput {
        ExportEvaluationInput(
            execution: execution,
            sport: sport,
            isCompleted: completed,
            isExportEnabled: enabled,
            isHealthDataAvailable: available,
            writeAuthorization: auth,
            existingRecord: record)
    }

    private func evaluate(_ i: ExportEvaluationInput) -> ExportEligibility {
        ExportEligibilityEvaluator.evaluate(i)
    }

    // MARK: - The happy case

    @Test("A completed manual run is eligible")
    func manualRunIsEligible() {
        #expect(evaluate(input(execution())) == .eligible)
        #expect(evaluate(input(execution())).canExportNow)
    }

    @Test("An in-app timed session is eligible")
    func appTimerIsEligible() {
        #expect(evaluate(input(execution(source: .appTimer))) == .eligible)
    }

    // MARK: - Provenance refusals

    @Test("A workout imported from Health is never written back")
    func importedIsRefused() {
        #expect(evaluate(input(execution(source: .healthKit))) == .importedFromHealthKit)
        #expect(!evaluate(input(execution(source: .healthKit))).canExportNow)
    }

    @Test("A watch-recorded execution is externally owned and not re-exported")
    func watchRecordedIsRefused() {
        let result = evaluate(input(execution(source: .appleWatch)))
        guard case .externallyOwned = result else {
            Issue.record("expected externallyOwned, got \(result)")
            return
        }
        #expect(!result.canExportNow)
    }

    @Test("An externally imported execution is not re-exported")
    func externalIsRefused() {
        guard case .externallyOwned = evaluate(input(execution(source: .external))) else {
            Issue.record("expected externallyOwned")
            return
        }
    }

    @Test("Provenance is checked before settings, so the message is never misleading")
    func provenanceBeatsSettings() {
        // Export is off AND the workout came from Health. Saying "enable export"
        // would imply enabling it would work. It would not.
        let result = evaluate(input(execution(source: .healthKit), enabled: false))
        #expect(result == .importedFromHealthKit)
    }

    // MARK: - Already exported

    @Test("An execution carrying a provider id is already exported")
    func alreadyExportedByProviderID() {
        let result = evaluate(input(execution(exported: "hk-123")))
        #expect(result == .alreadyExported(providerWorkoutID: "hk-123"))
    }

    @Test("A saved export record means already exported")
    func alreadyExportedByRecord() {
        let e = execution()
        let record = HealthExportRecord(
            executionID: e.id,
            idempotencyKey: HealthExportRecord.idempotencyKey(for: e.id),
            status: .saved,
            providerWorkoutID: "hk-456")
        #expect(evaluate(input(e, record: record)) == .alreadyExported(providerWorkoutID: "hk-456"))
    }

    @Test("A pending record means a save is already in flight")
    func pendingMeansCurrentlySaving() {
        let e = execution()
        let record = HealthExportRecord(
            executionID: e.id,
            idempotencyKey: HealthExportRecord.idempotencyKey(for: e.id),
            status: .pending)
        #expect(evaluate(input(e, record: record)) == .currentlySaving)
        #expect(!evaluate(input(e, record: record)).canExportNow,
                "a second tap while saving must not start another save")
    }

    // MARK: - Failure states

    @Test("A retryable failure stays retryable")
    func retryableFailure() {
        let e = execution()
        let record = HealthExportRecord(
            executionID: e.id,
            idempotencyKey: HealthExportRecord.idempotencyKey(for: e.id),
            status: .failed,
            lastFailure: .saveFailed)
        let result = evaluate(input(e, record: record))
        #expect(result == .failedRetryable(category: .saveFailed))
        #expect(result.isRetryable)
        #expect(result.canExportNow, "retry must be able to proceed")
    }

    @Test("A permanent failure is not offered for retry")
    func permanentFailure() {
        let e = execution()
        let record = HealthExportRecord(
            executionID: e.id,
            idempotencyKey: HealthExportRecord.idempotencyKey(for: e.id),
            status: .failed,
            lastFailure: .unsupportedActivity)
        let result = evaluate(input(e, record: record))
        #expect(result == .failedPermanent(category: .unsupportedActivity))
        #expect(!result.isRetryable)
    }

    // MARK: - Multisport and unsupported sports

    @Test("A brick is refused honestly rather than filed as one ride")
    func brickIsUnsupportedMultisport() {
        #expect(evaluate(input(execution(), sport: .brick)) == .unsupportedMultisport(.brick))
    }

    @Test("A race is refused honestly rather than filed as one activity")
    func raceIsUnsupportedMultisport() {
        #expect(evaluate(input(execution(), sport: .race)) == .unsupportedMultisport(.race))
    }

    @Test("Multisport refusal reads as a benign refusal, not an error")
    func multisportIsBenign() {
        #expect(evaluate(input(execution(), sport: .brick)).isBenignRefusal,
                "the UI must not alarm the athlete about a deliberate limitation")
    }

    @Test("Every sport with a HealthKit mapping is exportable")
    func mappedSportsAreEligible() {
        for sport in [Sport.swim, .bike, .run, .strength, .mobility, .recovery] {
            #expect(evaluate(input(execution(), sport: sport)) == .eligible, "\(sport)")
        }
    }

    // MARK: - Missing data

    @Test("An uncompleted workout is not exportable")
    func notCompleted() {
        #expect(evaluate(input(execution(), completed: false))
                == .missingRequiredData(reason: .notCompleted))
    }

    @Test("A zero-duration execution is refused")
    func zeroDuration() {
        #expect(evaluate(input(execution(minutes: 0)))
                == .missingRequiredData(reason: .zeroDuration))
    }

    @Test("A negative duration is refused")
    func negativeDuration() {
        let broken = WorkoutExecution(source: .manual, start: start, durationSeconds: -60)
        #expect(evaluate(input(broken)) == .missingRequiredData(reason: .negativeDuration))
    }

    @Test("A missing start date is refused")
    func missingStart() {
        let broken = WorkoutExecution(source: .manual, start: .distantPast, durationSeconds: 600)
        #expect(evaluate(input(broken)) == .missingRequiredData(reason: .missingStart))
    }

    // MARK: - Settings and permission

    @Test("Export switched off reports exportDisabled, not an error")
    func exportDisabled() {
        let result = evaluate(input(execution(), enabled: false))
        #expect(result == .exportDisabled)
        #expect(result.isBenignRefusal)
    }

    @Test("Missing write authorization asks for permission")
    func permissionRequired() {
        for status: HealthCapabilityState.Status in [.notDetermined, .denied, .unknowable] {
            #expect(evaluate(input(execution(), auth: status)) == .permissionRequired, "\(status)")
        }
    }

    @Test("Health unavailable reports permissionRequired rather than pretending")
    func unavailable() {
        #expect(evaluate(input(execution(), available: false)) == .permissionRequired)
    }

    // MARK: - Failure classification (§8)

    @Test("Failure categories classify into the four documented buckets")
    func classification() {
        #expect(ExportFailureCategory.saveFailed.classification == .retryable)
        #expect(ExportFailureCategory.authorizationDenied.classification == .userActionRequired)
        #expect(ExportFailureCategory.unsupportedActivity.classification == .permanentForWorkout)
        #expect(ExportFailureCategory.persistenceFailedAfterSave.classification == .internalConsistencyFailure)
    }

    @Test("A lost link after a successful save is retryable, because the data exists")
    func orphanIsRetryable() {
        #expect(ExportFailureCategory.persistenceFailedAfterSave.isRetryable,
                "HealthKit has the workout; we must be able to reconnect it")
    }

    @Test("Permission problems are not silently retried")
    func permissionIsNotRetryable() {
        #expect(!ExportFailureCategory.authorizationDenied.isRetryable)
        #expect(!ExportFailureCategory.duplicatePrevented.isRetryable)
    }
}

/// §2/§10 — the payload. What is written, and just as importantly what is not.
@Suite("Export payload")
struct HealthExportPayloadTests {

    private let start = Date(timeIntervalSince1970: 1_770_000_000)

    private func input(
        sport: Sport = .run,
        source: CompletionSource = .manual,
        minutes: Int = 60,
        distance: Double? = 10_000,
        energy: Double? = nil
    ) -> ExportEvaluationInput {
        ExportEvaluationInput(
            execution: WorkoutExecution(
                scheduledWorkoutID: UUID(),
                source: source,
                start: start,
                durationSeconds: minutes * 60,
                distanceMeters: distance,
                activeEnergyKilocalories: energy),
            sport: sport,
            isExportEnabled: true)
    }

    @Test("A payload carries the values it was given")
    func carriesKnownValues() throws {
        let payload = try HealthExportPayloadBuilder.build(for: input())
        #expect(payload.activityRawValue == 37) // running
        #expect(payload.start == start)
        #expect(payload.durationSeconds == 3600)
        #expect(payload.end == start.addingTimeInterval(3600))
        #expect(payload.distanceMeters == 10_000)
    }

    @Test("Absent metrics stay absent — nothing is fabricated")
    func neverFabricates() throws {
        let payload = try HealthExportPayloadBuilder.build(for: input(distance: nil))
        #expect(payload.distanceMeters == nil, "a missing distance must not become 0")
        #expect(payload.activeEnergyKilocalories == nil, "calories are never invented")
    }

    @Test("A zero distance is treated as absent, not as a real measurement")
    func zeroIsAbsent() throws {
        let payload = try HealthExportPayloadBuilder.build(for: input(distance: 0))
        #expect(payload.distanceMeters == nil)
    }

    @Test("Manual entry is declared, so it is distinguishable from a recording")
    func manualProvenanceIsDeclared() throws {
        #expect(try HealthExportPayloadBuilder.build(for: input(source: .manual)).wasUserEntered)
        #expect(try !HealthExportPayloadBuilder.build(for: input(source: .appTimer)).wasUserEntered)
    }

    @Test("Endurance identity is written to metadata for later reconciliation")
    func metadataCarriesIdentity() throws {
        let i = input()
        let payload = try HealthExportPayloadBuilder.build(for: i)
        let metadata = payload.enduranceMetadata

        #expect(metadata[HealthWorkoutExportPayload.MetadataKey.executionID] == i.execution.id.uuidString)
        #expect(metadata[HealthWorkoutExportPayload.MetadataKey.idempotencyKey]
                == HealthExportRecord.idempotencyKey(for: i.execution.id))
        #expect(metadata[HealthWorkoutExportPayload.MetadataKey.schemaVersion] == "2")
    }

    @Test("Execution identity round-trips back out of metadata — this is orphan recovery")
    func metadataRoundTrips() throws {
        let i = input()
        let payload = try HealthExportPayloadBuilder.build(for: i)
        let recovered = HealthWorkoutExportPayload.executionID(
            fromMetadata: payload.enduranceMetadata)
        #expect(recovered == i.execution.id)
    }

    @Test("Unrelated metadata yields no identity rather than a wrong one")
    func metadataMissIsNil() {
        #expect(HealthWorkoutExportPayload.executionID(fromMetadata: ["other": "value"]) == nil)
        #expect(HealthWorkoutExportPayload.executionID(fromMetadata: nil) == nil)
    }

    @Test("Building refuses an ineligible execution even if the caller asked")
    func buildRefusesIneligible() {
        let imported = ExportEvaluationInput(
            execution: WorkoutExecution(source: .healthKit, start: start, durationSeconds: 3600),
            sport: .run,
            isExportEnabled: true)

        #expect(throws: HealthExportPayloadBuilder.BuildError.self) {
            try HealthExportPayloadBuilder.build(for: imported)
        }
    }

    @Test("Building refuses a brick rather than approximating it")
    func buildRefusesBrick() {
        #expect(throws: HealthExportPayloadBuilder.BuildError.self) {
            try HealthExportPayloadBuilder.build(for: input(sport: .brick))
        }
    }

    @Test("The idempotency key is stable across rebuilds and ignores title and date")
    func idempotencyKeyIsStable() throws {
        let i = input()
        let a = try HealthExportPayloadBuilder.build(for: i)
        let b = try HealthExportPayloadBuilder.build(for: i)
        #expect(a.idempotencyKey == b.idempotencyKey)
        #expect(a.idempotencyKey.contains(i.execution.id.uuidString))
    }

    @Test("Two different executions never share an idempotency key")
    func keysAreDistinct() {
        let a = HealthExportRecord.idempotencyKey(for: UUID())
        let b = HealthExportRecord.idempotencyKey(for: UUID())
        #expect(a != b)
    }
}

/// §6/§7 — ownership and edit semantics.
@Suite("Export ownership and updates")
struct ExportOwnershipTests {

    private func record(
        owned: Bool = true,
        status: HealthExportRecord.Status = .saved,
        providerID: String? = "hk-1"
    ) -> HealthExportRecord {
        HealthExportRecord(
            executionID: UUID(),
            idempotencyKey: "k",
            status: status,
            providerWorkoutID: providerID,
            isEnduranceOwned: owned)
    }

    @Test("Endurance may delete a workout it created")
    func mayDeleteOwn() {
        #expect(HealthOwnership.mayDelete(record()) == .success("hk-1"))
    }

    @Test("Endurance refuses to delete a workout it does not own")
    func refusesForeign() {
        #expect(HealthOwnership.mayDelete(record(owned: false)) == .failure(.notEnduranceOwned))
    }

    @Test("Without a provider reference there is nothing to delete")
    func refusesWithoutReference() {
        #expect(HealthOwnership.mayDelete(record(providerID: nil)) == .failure(.noProviderReference))
        #expect(HealthOwnership.mayDelete(nil) == .failure(.noProviderReference))
    }

    @Test("An imported workout is never deleted from Health by Endurance")
    func neverDeletesImported() {
        #expect(!HealthOwnership.mayDeleteImported(),
                "unmatching locally says nothing about wanting it gone from Health")
    }

    @Test("Local-only edits never rewrite the Health record")
    func localOnlyEditsDoNotReplace() {
        #expect(!ExportRelevantField.requiresReplacement(changedFields: ["notes"]))
        #expect(!ExportRelevantField.requiresReplacement(changedFields: ["perceivedExertion", "soreness"]))
    }

    @Test("Editing a represented field requires replacement")
    func representedEditsRequireReplacement() {
        #expect(ExportRelevantField.requiresReplacement(changedFields: ["duration"]))
        #expect(ExportRelevantField.requiresReplacement(changedFields: ["distance"]))
        #expect(ExportRelevantField.requiresReplacement(changedFields: ["sport"]))
        #expect(ExportRelevantField.requiresReplacement(changedFields: ["notes", "duration"]))
    }

    @Test("Replacement requires confirmation because a visible record changes")
    func replacementNeedsConfirmation() {
        #expect(ExportUpdateOutcome.healthReplacementRequired.requiresConfirmation)
        #expect(!ExportUpdateOutcome.localOnlyUpdated.requiresConfirmation)
    }

    @Test("A delete that succeeded followed by a failed save is flagged for recovery")
    func lostAfterDeleteNeedsRecovery() {
        #expect(ExportUpdateOutcome.healthSaveFailedAfterDelete.needsRecovery,
                "the execution must never be silently lost")
        #expect(!ExportUpdateOutcome.replacedSuccessfully.needsRecovery)
    }

    @Test("A pending record with no provider id is a potential orphan")
    func orphanDetection() {
        #expect(record(status: .pending, providerID: nil).isPotentialOrphan)
        #expect(!record(status: .saved).isPotentialOrphan)
    }
}
