import Foundation

/// Decides whether an imported external activity corresponds to a planned
/// session (§E).
///
/// Two rules shape the whole design:
///   * **Explainable.** Every result carries the evidence that produced it, so
///     the UI can say *why* rather than showing a bare percentage, and so a user
///     can disagree with something concrete.
///   * **Conservative.** Sport plus calendar day is explicitly not enough to
///     auto-match (§E). Only a previously established provider link, or a close
///     agreement on start time *and* duration, may apply without confirmation.
public struct WorkoutMatcher: Sendable {

    // MARK: - Result vocabulary

    public enum Confidence: String, Codable, Sendable, Hashable, CaseIterable {
        /// A provider link already exists, or the agreement is unambiguous.
        case exact
        /// Strong agreement; may be suggested automatically but stays reversible.
        case high
        /// Plausible, but the athlete must decide.
        case possible
        /// Nothing plausible in range.
        case none
        /// Plausible, but the planned session already has a different execution.
        case conflict
        /// This external activity has already been recorded.
        case duplicate

        /// Whether the app may apply this without asking (§E).
        public var mayApplyAutomatically: Bool {
            switch self {
            case .exact: return true
            case .high, .possible, .none, .conflict, .duplicate: return false
            }
        }

        /// Whether the app may *suggest* this, pending confirmation.
        public var isSuggestable: Bool {
            switch self {
            case .exact, .high, .possible: return true
            case .none, .conflict, .duplicate: return false
            }
        }

        public var localizationKey: String { "match.\(rawValue)" }
    }

    /// A single piece of evidence, so the UI can explain the decision.
    public struct Reason: Codable, Sendable, Hashable, Identifiable {
        public enum Kind: String, Codable, Sendable {
            case providerLinkExists
            case sportMatches
            case sportDiffers
            case startTimeClose
            case startTimeFar
            case durationClose
            case durationFar
            case distanceClose
            case distanceFar
            case alreadyExecuted
            case alreadyImported
            case outsideWindow
        }
        public var id: String { kind.rawValue }
        public var kind: Kind
        /// Human-facing detail, e.g. "12 min apart". Localized at the UI edge.
        public var detail: String?

        public init(kind: Kind, detail: String? = nil) {
            self.kind = kind
            self.detail = detail
        }
    }

    public struct Match: Sendable, Hashable {
        public var scheduledWorkoutID: UUID?
        public var confidence: Confidence
        public var reasons: [Reason]
        /// 0...1, for ordering candidates only — never shown as a bare number.
        public var score: Double

        public init(scheduledWorkoutID: UUID?, confidence: Confidence, reasons: [Reason], score: Double) {
            self.scheduledWorkoutID = scheduledWorkoutID
            self.confidence = confidence
            self.reasons = reasons
            self.score = score
        }
    }

    // MARK: - Tolerances

    public struct Tolerances: Sendable, Hashable {
        /// How far from the planned start a session may begin and still be
        /// considered the same session.
        public var startWindow: TimeInterval
        /// Within this, start time is "close".
        public var startClose: TimeInterval
        /// Fractional duration agreement, e.g. 0.25 = within 25%.
        public var durationTolerance: Double
        /// Fractional distance agreement.
        public var distanceTolerance: Double

        public init(
            startWindow: TimeInterval = 6 * 60 * 60,
            startClose: TimeInterval = 45 * 60,
            durationTolerance: Double = 0.25,
            distanceTolerance: Double = 0.20
        ) {
            self.startWindow = startWindow
            self.startClose = startClose
            self.durationTolerance = durationTolerance
            self.distanceTolerance = distanceTolerance
        }

        public static let `default` = Tolerances()
    }

    public let tolerances: Tolerances
    private let calendar: Calendar

    public init(tolerances: Tolerances = .default, calendar: Calendar = Calendar(identifier: .gregorian)) {
        self.tolerances = tolerances
        self.calendar = calendar
    }

    // MARK: - Matching

    /// Rank candidate planned sessions for one external activity.
    ///
    /// `existingLinks` maps an idempotency key to the scheduled workout it is
    /// already attached to; `executedWorkoutIDs` are sessions that already have
    /// an execution recorded from a *different* source.
    public func match(
        _ summary: ExternalWorkoutSummary,
        against candidates: [ScheduledWorkout],
        existingLinks: [String: UUID] = [:],
        executedWorkoutIDs: Set<UUID> = [],
        alreadyImportedKeys: Set<String> = []
    ) -> Match {

        // 1. Already imported — idempotency short-circuit (§O).
        if alreadyImportedKeys.contains(summary.idempotencyKey) {
            return Match(
                scheduledWorkoutID: existingLinks[summary.idempotencyKey],
                confidence: .duplicate,
                reasons: [Reason(kind: .alreadyImported)],
                score: 1)
        }

        // 2. An established provider link is authoritative.
        if let linked = existingLinks[summary.idempotencyKey] {
            return Match(
                scheduledWorkoutID: linked,
                confidence: .exact,
                reasons: [Reason(kind: .providerLinkExists)],
                score: 1)
        }

        // 3. Score every candidate within the window.
        let scored = candidates.compactMap { candidate -> Match? in
            evaluate(summary, candidate, executedWorkoutIDs: executedWorkoutIDs)
        }
        .sorted { $0.score > $1.score }

        guard let best = scored.first else {
            return Match(scheduledWorkoutID: nil,
                         confidence: .none,
                         reasons: [Reason(kind: .outsideWindow)],
                         score: 0)
        }

        // 4. If two candidates are near-indistinguishable, do not guess.
        if scored.count > 1, scored[1].score > 0, best.score - scored[1].score < 0.10 {
            return Match(scheduledWorkoutID: best.scheduledWorkoutID,
                         confidence: .possible,
                         reasons: best.reasons,
                         score: best.score)
        }
        return best
    }

    private func evaluate(
        _ summary: ExternalWorkoutSummary,
        _ candidate: ScheduledWorkout,
        executedWorkoutIDs: Set<UUID>
    ) -> Match? {
        var reasons: [Reason] = []
        var score = 0.0

        // Sport is a gate, not a score: a swim is never a run.
        guard sportsAgree(summary.sport, candidate.sport) else { return nil }
        reasons.append(Reason(kind: .sportMatches))
        score += 0.30

        let startDelta = abs(summary.start.timeIntervalSince(candidate.plannedStart))
        guard startDelta <= tolerances.startWindow else { return nil }

        if startDelta <= tolerances.startClose {
            reasons.append(Reason(kind: .startTimeClose, detail: minutesDescription(startDelta)))
            score += 0.35
        } else {
            reasons.append(Reason(kind: .startTimeFar, detail: minutesDescription(startDelta)))
            score += 0.10
        }

        let plannedSeconds = Double(candidate.effectivePlannedMinutes * 60)
        if plannedSeconds > 0 {
            let ratio = abs(Double(summary.durationSeconds) - plannedSeconds) / plannedSeconds
            if ratio <= tolerances.durationTolerance {
                reasons.append(Reason(kind: .durationClose, detail: percentDescription(ratio)))
                score += 0.25
            } else {
                reasons.append(Reason(kind: .durationFar, detail: percentDescription(ratio)))
            }
        }

        if let actual = summary.distanceMeters, let planned = candidate.plannedDistanceMeters, planned > 0 {
            let ratio = abs(actual - planned) / planned
            if ratio <= tolerances.distanceTolerance {
                reasons.append(Reason(kind: .distanceClose, detail: percentDescription(ratio)))
                score += 0.10
            } else {
                reasons.append(Reason(kind: .distanceFar, detail: percentDescription(ratio)))
            }
        }

        // Already executed from another source → conflict, never a silent replace.
        if executedWorkoutIDs.contains(candidate.id) {
            reasons.append(Reason(kind: .alreadyExecuted))
            return Match(scheduledWorkoutID: candidate.id, confidence: .conflict, reasons: reasons, score: score)
        }

        return Match(scheduledWorkoutID: candidate.id,
                     confidence: confidence(for: score, reasons: reasons),
                     reasons: reasons,
                     score: min(score, 1))
    }

    /// Sport plus day is never enough on its own (§E), so `high` additionally
    /// requires both a close start time and a close duration.
    private func confidence(for score: Double, reasons: [Reason]) -> Confidence {
        let kinds = Set(reasons.map(\.kind))
        let startClose = kinds.contains(.startTimeClose)
        let durationClose = kinds.contains(.durationClose)

        if startClose && durationClose && score >= 0.85 { return .high }
        if startClose || durationClose { return .possible }
        return .possible
    }

    /// A brick session records as a ride or a run depending on which leg the
    /// device captured, so both map onto a planned brick.
    private func sportsAgree(_ imported: Sport, _ planned: Sport) -> Bool {
        if imported == planned { return true }
        if planned == .brick { return imported == .bike || imported == .run }
        if planned == .race { return imported == .swim || imported == .bike || imported == .run }
        // Walking stands in for an easy run or a recovery session.
        if imported == .recovery && (planned == .recovery || planned == .mobility) { return true }
        return false
    }

    private func minutesDescription(_ interval: TimeInterval) -> String {
        "\(Int((interval / 60).rounded())) min"
    }

    private func percentDescription(_ ratio: Double) -> String {
        "\(Int((ratio * 100).rounded()))%"
    }
}

// MARK: - User decisions

/// A decision the athlete made about a suggested match, persisted so the same
/// suggestion does not keep returning (§E).
public struct WorkoutMatchDecision: Codable, Sendable, Hashable, Identifiable {
    public enum Outcome: String, Codable, Sendable {
        case confirmed
        case rejected
        case keptAsUnplanned
        case merged
        case undone
    }

    public var id: UUID
    /// The external activity this decision is about.
    public var idempotencyKey: String
    public var scheduledWorkoutID: UUID?
    public var outcome: Outcome
    public var decidedAt: Date
    /// What the engine had suggested, for auditability.
    public var suggestedConfidence: WorkoutMatcher.Confidence?

    public init(
        id: UUID = UUID(),
        idempotencyKey: String,
        scheduledWorkoutID: UUID?,
        outcome: Outcome,
        decidedAt: Date = Date(),
        suggestedConfidence: WorkoutMatcher.Confidence? = nil
    ) {
        self.id = id
        self.idempotencyKey = idempotencyKey
        self.scheduledWorkoutID = scheduledWorkoutID
        self.outcome = outcome
        self.decidedAt = decidedAt
        self.suggestedConfidence = suggestedConfidence
    }

    /// A rejected or already-handled activity should not be re-suggested.
    public var suppressesFutureSuggestions: Bool {
        switch outcome {
        case .confirmed, .rejected, .keptAsUnplanned, .merged: return true
        case .undone: return false
        }
    }
}
