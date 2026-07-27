import Foundation
import EnduranceDomain

/// Decides what an incremental import actually changed (§D, §O).
///
/// Duplicate prevention is release-critical, and the failure mode is specific:
/// one execution observed through two Apple frameworks must never show up as two
/// completed workouts. Every defence lives here, in pure logic, so each pathway
/// §O lists can be asserted directly rather than reproduced on a wrist.
public struct ImportReconciler: Sendable {

    /// What the app should do as a result of one import batch.
    public struct Outcome: Sendable, Equatable {
        /// Activities never seen before, worth showing in the Health Inbox.
        public var newSummaries: [ExternalWorkoutSummary] = []
        /// Activities already known whose source data changed.
        public var updatedSummaries: [ExternalWorkoutSummary] = []
        /// Known activities deleted at source.
        public var deletedKeys: [String] = []
        /// Skipped because Endurance wrote them itself.
        public var skippedSelfAuthored: [String] = []
        /// Skipped as too short to be a real session.
        public var skippedTooShort: [String] = []
        /// Re-delivered by the anchored query but unchanged — the common case
        /// after an app relaunch.
        public var unchangedKeys: [String] = []

        public var hasChanges: Bool {
            !newSummaries.isEmpty || !updatedSummaries.isEmpty || !deletedKeys.isEmpty
        }
    }

    /// What the app already knows, keyed by idempotency key.
    public struct KnownState: Sendable {
        public var summaries: [String: ExternalWorkoutSummary]
        /// External keys already attached to a local execution — i.e. this
        /// activity is already represented as completed training.
        public var executionKeys: Set<String>

        public init(
            summaries: [String: ExternalWorkoutSummary] = [:],
            executionKeys: Set<String> = []
        ) {
            self.summaries = summaries
            self.executionKeys = executionKeys
        }
    }

    public let appBundleIdentifier: String

    public init(appBundleIdentifier: String) {
        self.appBundleIdentifier = appBundleIdentifier
    }

    public func reconcile(_ batch: HealthImportBatch, known: KnownState) -> Outcome {
        var outcome = Outcome()

        for summary in batch.summaries {
            let key = summary.idempotencyKey

            // 1. Endurance's own exports must never come back in as imports.
            //    Without this, every workout the user exports reappears as an
            //    unmatched activity in the inbox (§O).
            if HealthImportFilter.isSelfAuthored(summary, appBundleID: appBundleIdentifier) {
                outcome.skippedSelfAuthored.append(key)
                continue
            }

            // 2. Already represented as completed training — nothing to review.
            if known.executionKeys.contains(key) {
                outcome.unchangedKeys.append(key)
                continue
            }

            if let existing = known.summaries[key] {
                // 3. Re-delivery after relaunch: same revision, nothing changed.
                if isUnchanged(existing, summary) {
                    outcome.unchangedKeys.append(key)
                } else {
                    outcome.updatedSummaries.append(summary)
                }
                continue
            }

            // 4. Genuinely new — but still filter noise.
            guard HealthImportFilter.isWorthImporting(summary) else {
                outcome.skippedTooShort.append(key)
                continue
            }
            outcome.newSummaries.append(summary)
        }

        // 5. Deletions only matter for things we actually knew about.
        outcome.deletedKeys = batch.deletedProviderIDs
            .map { "\(batch.updatedCursor.provider.rawValue):\($0)" }
            .filter { known.summaries[$0] != nil }

        return outcome
    }

    /// Two observations are the same when the provider's revision agrees, or —
    /// when the provider exposes no revision — when the fields we care about do.
    private func isUnchanged(_ existing: ExternalWorkoutSummary, _ incoming: ExternalWorkoutSummary) -> Bool {
        if let a = existing.sourceRevision, let b = incoming.sourceRevision {
            return a == b
        }
        return existing.start == incoming.start
            && existing.durationSeconds == incoming.durationSeconds
            && existing.distanceMeters == incoming.distanceMeters
            && existing.isDeletedAtSource == incoming.isDeletedAtSource
    }
}

/// Reconciles executions arriving from different sources for the *same* physical
/// session (§O).
///
/// The canonical case: the Watch saves a ride to HealthKit and separately syncs
/// its completion to the phone. Both describe one ride. Whichever arrives first
/// creates the execution; the second must attach to it, not create a twin.
public struct ExecutionMerger: Sendable {

    public enum Resolution: Sendable, Equatable {
        /// No existing execution — create this one.
        case insert(WorkoutExecution)
        /// An existing execution already covers this observation; attach the key.
        case attach(existingID: UUID, externalKey: String?)
        /// Exactly this observation is already recorded. Do nothing.
        case ignore(existingID: UUID)
    }

    /// How close two starts must be to be considered the same session.
    public let coincidenceWindow: TimeInterval

    public init(coincidenceWindow: TimeInterval = 10 * 60) {
        self.coincidenceWindow = coincidenceWindow
    }

    public func resolve(
        incoming: WorkoutExecution,
        externalKey: String?,
        against existing: [WorkoutExecution]
    ) -> Resolution {

        // 1. Same execution identity — e.g. a retried watch transfer, or the
        //    user tapping save twice.
        if let match = existing.first(where: { $0.id == incoming.id }) {
            if let externalKey, !match.externalKeys.contains(externalKey) {
                return .attach(existingID: match.id, externalKey: externalKey)
            }
            return .ignore(existingID: match.id)
        }

        // 2. This external observation is already attached to some execution —
        //    e.g. HealthKit import seeing a workout the watch already synced.
        if let externalKey,
           let match = existing.first(where: { $0.externalKeys.contains(externalKey) }) {
            return .ignore(existingID: match.id)
        }

        // 3. Same planned session, same sport, overlapping time — one session
        //    observed twice through different frameworks.
        if let match = existing.first(where: { coincides(incoming, $0) }) {
            return .attach(existingID: match.id, externalKey: externalKey)
        }

        return .insert(incoming)
    }

    private func coincides(_ a: WorkoutExecution, _ b: WorkoutExecution) -> Bool {
        // Both attached to the same planned session is strong evidence, but only
        // when they also overlap in time — an athlete may legitimately repeat a
        // session later in the day.
        let sameSession = a.scheduledWorkoutID != nil && a.scheduledWorkoutID == b.scheduledWorkoutID
        let startsClose = abs(a.start.timeIntervalSince(b.start)) <= coincidenceWindow
        if sameSession && startsClose { return true }

        // Unplanned training: near-identical start and duration.
        guard startsClose else { return false }
        let durationDelta = abs(Double(a.durationSeconds - b.durationSeconds))
        return durationDelta <= 120
    }
}
