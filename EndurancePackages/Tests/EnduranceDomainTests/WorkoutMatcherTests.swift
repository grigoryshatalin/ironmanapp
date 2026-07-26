import Testing
import Foundation
@testable import EnduranceDomain

/// §E — matching imported activities to planned sessions. The rules that matter
/// most are the *refusals*: never auto-match on sport + day alone, never match
/// one activity to two sessions, never silently replace an existing completion.
@Suite("Health workout matching")
struct WorkoutMatcherTests {

    private let tz = "America/New_York"
    private let matcher = WorkoutMatcher()

    private func planned(
        sport: Sport = .run,
        start: Date,
        minutes: Int = 60,
        distance: Double? = nil,
        name: String = "session"
    ) -> ScheduledWorkout {
        ScheduledFactory.make(
            name: name,
            sport: sport,
            stress: .moderate,
            start: start,
            durationMinutes: minutes,
            distanceMeters: distance)
    }

    private func imported(
        sport: Sport = .run,
        start: Date,
        minutes: Int = 60,
        distance: Double? = nil,
        providerID: String = "hk-1"
    ) -> ExternalWorkoutSummary {
        ExternalWorkoutSummary(
            provider: .healthKit,
            providerWorkoutID: providerID,
            sport: sport,
            start: start,
            end: start.addingTimeInterval(Double(minutes) * 60),
            durationSeconds: minutes * 60,
            distanceMeters: distance,
            importedAt: Date(),
            lastObservedAt: Date())
    }

    // MARK: - Established identity wins

    @Test("An existing provider link matches exactly and needs no heuristics")
    func providerLinkIsAuthoritative() {
        let start = TestDates.date(2026, 5, 12, 7, 0, tz: tz)
        let session = planned(start: start)
        let activity = imported(start: start.addingTimeInterval(9 * 3600)) // deliberately far

        let result = matcher.match(
            activity,
            against: [session],
            existingLinks: [activity.idempotencyKey: session.id])

        #expect(result.confidence == .exact)
        #expect(result.scheduledWorkoutID == session.id)
        #expect(result.confidence.mayApplyAutomatically)
    }

    @Test("An already-imported activity is reported as a duplicate, not re-matched")
    func duplicateIsShortCircuited() {
        let start = TestDates.date(2026, 5, 12, 7, 0, tz: tz)
        let session = planned(start: start)
        let activity = imported(start: start)

        let result = matcher.match(
            activity,
            against: [session],
            alreadyImportedKeys: [activity.idempotencyKey])

        #expect(result.confidence == .duplicate)
        #expect(!result.confidence.mayApplyAutomatically)
        #expect(!result.confidence.isSuggestable)
    }

    // MARK: - The central refusal

    @Test("Sport and calendar day alone never auto-match")
    func sportAndDayAloneIsNotEnough() {
        let planStart = TestDates.date(2026, 5, 12, 6, 30, tz: tz)
        // Same day, same sport, but hours apart and a very different duration.
        let activity = imported(start: TestDates.date(2026, 5, 12, 11, 30, tz: tz), minutes: 20)
        let session = planned(start: planStart, minutes: 90)

        let result = matcher.match(activity, against: [session])

        #expect(result.confidence != .exact)
        #expect(result.confidence != .high)
        #expect(!result.confidence.mayApplyAutomatically,
                "sport + day agreement must never be applied without confirmation")
    }

    @Test("A different sport is never matched")
    func differentSportIsRejected() {
        let start = TestDates.date(2026, 5, 12, 7, 0, tz: tz)
        let result = matcher.match(
            imported(sport: .swim, start: start),
            against: [planned(sport: .run, start: start)])

        #expect(result.confidence == .none)
        #expect(result.scheduledWorkoutID == nil)
    }

    @Test("An activity far outside the window matches nothing")
    func outsideWindowIsNoMatch() {
        let planStart = TestDates.date(2026, 5, 12, 6, 30, tz: tz)
        let activity = imported(start: TestDates.date(2026, 5, 14, 6, 30, tz: tz))
        let result = matcher.match(activity, against: [planned(start: planStart)])

        #expect(result.confidence == .none)
    }

    // MARK: - Strong agreement

    @Test("Close start time and duration give a high-confidence, reversible suggestion")
    func closeAgreementIsHighConfidence() {
        let planStart = TestDates.date(2026, 5, 12, 6, 30, tz: tz)
        let activity = imported(
            start: planStart.addingTimeInterval(5 * 60), // 5 min late
            minutes: 62,                                  // ~3% off 60
            distance: 10_200)
        let session = planned(start: planStart, minutes: 60, distance: 10_000)

        let result = matcher.match(activity, against: [session])

        #expect(result.confidence == .high)
        #expect(result.scheduledWorkoutID == session.id)
        #expect(result.confidence.isSuggestable)
        #expect(!result.confidence.mayApplyAutomatically, "high confidence still requires confirmation")

        let kinds = Set(result.reasons.map(\.kind))
        #expect(kinds.contains(.startTimeClose))
        #expect(kinds.contains(.durationClose))
        #expect(kinds.contains(.sportMatches))
    }

    @Test("Every result carries explaining evidence")
    func resultsAreExplainable() {
        let planStart = TestDates.date(2026, 5, 12, 6, 30, tz: tz)
        let result = matcher.match(
            imported(start: planStart.addingTimeInterval(120), minutes: 58),
            against: [planned(start: planStart, minutes: 60)])

        #expect(!result.reasons.isEmpty, "a match with no stated reason cannot be reviewed")
        #expect(result.reasons.contains { $0.detail != nil }, "at least one reason should be specific")
    }

    // MARK: - Conflicts and ambiguity

    @Test("A session that already has an execution reports a conflict, never a replace")
    func existingExecutionIsAConflict() {
        let planStart = TestDates.date(2026, 5, 12, 6, 30, tz: tz)
        let session = planned(start: planStart)
        let activity = imported(start: planStart.addingTimeInterval(60))

        let result = matcher.match(
            activity,
            against: [session],
            executedWorkoutIDs: [session.id])

        #expect(result.confidence == .conflict)
        #expect(!result.confidence.mayApplyAutomatically)
        #expect(result.reasons.contains { $0.kind == .alreadyExecuted })
    }

    @Test("Two near-identical candidates degrade to a user decision")
    func ambiguityRequiresTheUser() {
        let planStart = TestDates.date(2026, 5, 12, 6, 30, tz: tz)
        // Two identical planned runs 10 minutes apart — genuinely ambiguous.
        let a = planned(start: planStart, minutes: 60, name: "run-a")
        let b = planned(start: planStart.addingTimeInterval(600), minutes: 60, name: "run-b")
        let activity = imported(start: planStart.addingTimeInterval(300), minutes: 60)

        let result = matcher.match(activity, against: [a, b])

        #expect(result.confidence == .possible,
                "indistinguishable candidates must not be auto-resolved")
        #expect(!result.confidence.mayApplyAutomatically)
    }

    // MARK: - Sport equivalences

    @Test("A brick accepts either the ride or the run leg")
    func brickAcceptsBothLegs() {
        let planStart = TestDates.date(2026, 5, 16, 8, 0, tz: tz)
        let brick = planned(sport: .brick, start: planStart, minutes: 90)

        for leg in [Sport.bike, Sport.run] {
            let result = matcher.match(
                imported(sport: leg, start: planStart.addingTimeInterval(120), minutes: 88),
                against: [brick])
            #expect(result.scheduledWorkoutID == brick.id, "\(leg) should match a brick")
        }
    }

    @Test("A swim is not accepted for a planned ride even on the right day")
    func brickDoesNotAcceptUnrelatedSport() {
        let planStart = TestDates.date(2026, 5, 16, 8, 0, tz: tz)
        let result = matcher.match(
            imported(sport: .swim, start: planStart, minutes: 60),
            against: [planned(sport: .bike, start: planStart, minutes: 60)])
        #expect(result.confidence == .none)
    }
}

/// §E — decisions must persist so a rejected suggestion does not keep returning.
@Suite("Match decisions")
struct WorkoutMatchDecisionTests {

    @Test("Confirmed, rejected, kept and merged all suppress re-suggestion")
    func decisionsSuppressResuggestion() {
        for outcome: WorkoutMatchDecision.Outcome in [.confirmed, .rejected, .keptAsUnplanned, .merged] {
            let decision = WorkoutMatchDecision(
                idempotencyKey: "healthKit:abc", scheduledWorkoutID: UUID(), outcome: outcome)
            #expect(decision.suppressesFutureSuggestions, "\(outcome) should not re-suggest")
        }
    }

    @Test("Undoing a decision allows the suggestion to return")
    func undoRestoresSuggestion() {
        let decision = WorkoutMatchDecision(
            idempotencyKey: "healthKit:abc", scheduledWorkoutID: nil, outcome: .undone)
        #expect(!decision.suppressesFutureSuggestions)
    }

    @Test("Match decisions survive an encode/decode round trip")
    func decisionRoundTrips() throws {
        let decision = WorkoutMatchDecision(
            idempotencyKey: "healthKit:abc",
            scheduledWorkoutID: UUID(),
            outcome: .confirmed,
            suggestedConfidence: .high)
        let data = try JSONEncoder().encode(decision)
        let back = try JSONDecoder().decode(WorkoutMatchDecision.self, from: data)
        #expect(back == decision)
    }
}

/// §F — export eligibility. The rule that must never break: an activity that came
/// from HealthKit is never written back to HealthKit.
@Suite("Health export eligibility")
struct HealthExportEligibilityTests {

    private func execution(source: CompletionSource, exported: String? = nil) -> WorkoutExecution {
        WorkoutExecution(
            source: source,
            start: Date(),
            durationSeconds: 3600,
            exportedProviderID: exported)
    }

    @Test("Manual and in-app timer executions may be exported")
    func locallyCreatedIsEligible() {
        #expect(execution(source: .manual).isEligibleForHealthExport)
        #expect(execution(source: .appTimer).isEligibleForHealthExport)
    }

    @Test("Imported and watch-recorded executions are never re-exported")
    func externallySourcedIsNotEligible() {
        #expect(!execution(source: .healthKit).isEligibleForHealthExport)
        #expect(!execution(source: .appleWatch).isEligibleForHealthExport)
        #expect(!execution(source: .external).isEligibleForHealthExport)
    }

    @Test("An already-exported execution is not exported twice")
    func alreadyExportedIsNotEligible() {
        #expect(!execution(source: .manual, exported: "hk-uuid").isEligibleForHealthExport)
    }

    @Test("The idempotency key is stable and provider-scoped")
    func idempotencyKeyIsStable() {
        let summary = ExternalWorkoutSummary(
            provider: .healthKit, providerWorkoutID: "ABC",
            sport: .run, start: Date(), end: Date(), durationSeconds: 60,
            importedAt: Date(), lastObservedAt: Date())
        #expect(summary.idempotencyKey == "healthKit:ABC")

        // The same provider id under a different provider is a different thing.
        var other = summary
        other.provider = .strava
        #expect(other.idempotencyKey != summary.idempotencyKey)
    }
}
