import Testing
import Foundation
@testable import EnduranceDomain

/// §G — the active-workout state machine. The valuable assertions here are the
/// *illegal* transitions: a workout that can be discarded after it saved, or
/// resumed after it ended, is how real data gets lost.
@Suite("Active workout state machine")
struct ActiveWorkoutStateMachineTests {

    @Test("A normal session runs start → running → ending → saving → completed")
    func happyPath() throws {
        var machine = ActiveWorkoutMachine()
        try machine.apply(.start)
        #expect(machine.state == .starting)
        try machine.apply(.sessionDidStart)
        #expect(machine.state == .running)
        try machine.apply(.end)
        #expect(machine.state == .ending)
        try machine.apply(.sessionDidEnd)
        #expect(machine.state == .saving)
        try machine.apply(.saveSucceeded)
        #expect(machine.state == .completed)
        #expect(machine.state.isTerminal)
    }

    @Test("Pause and resume return to running")
    func pauseResume() throws {
        var machine = ActiveWorkoutMachine(state: .running)
        try machine.apply(.pause)
        #expect(machine.state == .paused)
        #expect(!machine.state.isAccruingTime)
        try machine.apply(.resume)
        #expect(machine.state == .resuming)
        try machine.apply(.sessionDidResume)
        #expect(machine.state == .running)
        #expect(machine.state.isAccruingTime)
    }

    @Test("A completed workout can never be discarded — that would be data loss")
    func completedCannotBeDiscarded() {
        var machine = ActiveWorkoutMachine(state: .completed)
        #expect(!machine.canApply(.discard))
        #expect(throws: ActiveWorkoutMachine.TransitionError.self) {
            try machine.apply(.discard)
        }
    }

    @Test("A terminal state accepts no further events at all")
    func terminalStatesAreFinal() {
        for terminal in [ActiveWorkoutState.completed, .discarded] {
            let machine = ActiveWorkoutMachine(state: terminal)
            for event in ActiveWorkoutEvent.allCases {
                #expect(!machine.canApply(event),
                        "\(terminal) should reject \(event)")
            }
        }
    }

    @Test("An idle workout cannot be paused, resumed, or ended")
    func idleRejectsLifecycleEvents() {
        let machine = ActiveWorkoutMachine(state: .idle)
        for event: ActiveWorkoutEvent in [.pause, .resume, .end, .sessionDidEnd, .saveSucceeded] {
            #expect(!machine.canApply(event), "idle should reject \(event)")
        }
    }

    @Test("A failed save keeps the data and stays retryable")
    func failedSaveIsRetryable() throws {
        var machine = ActiveWorkoutMachine(state: .saving)
        try machine.apply(.saveFailed)
        #expect(machine.state == .failed)
        #expect(!machine.state.isTerminal, "a failed save must not silently drop the workout")
        try machine.apply(.retry)
        #expect(machine.state == .saving)
    }

    @Test("Discard is allowed up to and including saving, but not after success")
    func discardWindow() {
        for state: ActiveWorkoutState in [.preparing, .running, .paused, .ending, .saving, .failed] {
            #expect(ActiveWorkoutMachine(state: state).canApply(.discard),
                    "\(state) should allow discard")
        }
        #expect(!ActiveWorkoutMachine(state: .completed).canApply(.discard))
    }

    @Test("Any live state can be interrupted into recovery")
    func interruptionLeadsToRecovery() throws {
        for state: ActiveWorkoutState in [.starting, .running, .paused, .resuming, .ending] {
            var machine = ActiveWorkoutMachine(state: state)
            try machine.apply(.interrupted)
            #expect(machine.state == .recovering, "\(state) should recover")
        }
    }

    @Test("Recovery can resume, end, or discard — but never fabricate a completion")
    func recoveryOptions() {
        let machine = ActiveWorkoutMachine(state: .recovering)
        #expect(machine.canApply(.recovered))
        #expect(machine.canApply(.end))
        #expect(machine.canApply(.discard))
        #expect(!machine.canApply(.saveSucceeded),
                "recovery must not jump straight to completed")
    }

    @Test("Only running and resuming accrue workout time")
    func timeAccrual() {
        for state in ActiveWorkoutState.allCases {
            let expected = (state == .running || state == .resuming)
            #expect(state.isAccruingTime == expected, "\(state)")
        }
    }

    @Test("isActive marks exactly the states that should own a Live Activity")
    func activeStates() {
        #expect(ActiveWorkoutState.running.isActive)
        #expect(ActiveWorkoutState.paused.isActive)
        #expect(ActiveWorkoutState.recovering.isActive)
        #expect(!ActiveWorkoutState.idle.isActive)
        #expect(!ActiveWorkoutState.completed.isActive)
        #expect(!ActiveWorkoutState.discarded.isActive)
        #expect(!ActiveWorkoutState.failed.isActive)
    }
}

/// §G — elapsed time must come from a monotonic clock, not wall-clock deltas.
@Suite("Monotonic elapsed time")
struct MonotonicStopwatchTests {

    private let second: UInt64 = 1_000_000_000

    @Test("Elapsed time accrues only while running")
    func accruesWhileRunning() {
        var watch = MonotonicStopwatch()
        watch.start(now: 0)
        #expect(watch.elapsed(now: 10 * second) == 10)
        watch.pause(now: 10 * second)
        // Time passes while paused; elapsed must not move.
        #expect(watch.elapsed(now: 60 * second) == 10)
    }

    @Test("Resuming continues from the accumulated total")
    func resumeAccumulates() {
        var watch = MonotonicStopwatch()
        watch.start(now: 0)
        watch.pause(now: 30 * second)
        watch.start(now: 100 * second)
        #expect(watch.elapsed(now: 130 * second) == 60)
    }

    @Test("A clock that appears to go backwards contributes nothing, never negative time")
    func backwardsClockIsIgnored() {
        var watch = MonotonicStopwatch()
        watch.start(now: 100 * second)
        #expect(watch.elapsed(now: 50 * second) == 0,
                "elapsed time must never go negative")
    }

    @Test("Double start and double pause are harmless")
    func idempotentControls() {
        var watch = MonotonicStopwatch()
        watch.start(now: 0)
        watch.start(now: 5 * second) // ignored
        #expect(watch.elapsed(now: 10 * second) == 10)
        watch.pause(now: 10 * second)
        watch.pause(now: 20 * second) // ignored
        #expect(watch.elapsed(now: 30 * second) == 10)
    }

    @Test("Accumulated seconds persist for recovery")
    func accumulatedIsPersistable() {
        var watch = MonotonicStopwatch()
        watch.start(now: 0)
        watch.pause(now: 42 * second)
        #expect(watch.accumulatedSeconds == 42)

        // Rehydrate as if after termination.
        var restored = MonotonicStopwatch(accumulated: watch.accumulatedSeconds)
        restored.start(now: 1000 * second)
        #expect(restored.elapsed(now: 1010 * second) == 52)
    }
}

/// §G — recovery records.
@Suite("Active workout recovery")
struct ActiveWorkoutRecoveryTests {

    private func record(state: ActiveWorkoutState) -> ActiveWorkoutRecovery {
        ActiveWorkoutRecovery(
            scheduledWorkoutID: UUID(),
            executionID: UUID(),
            state: state,
            sport: .run,
            startedAt: Date(),
            accumulatedSeconds: 120)
    }

    @Test("Live states need recovery; finished ones do not")
    func needsRecovery() {
        #expect(record(state: .running).needsRecovery)
        #expect(record(state: .paused).needsRecovery)
        #expect(record(state: .saving).needsRecovery)
        #expect(!record(state: .completed).needsRecovery)
        #expect(!record(state: .discarded).needsRecovery)
        #expect(!record(state: .idle).needsRecovery)
    }

    @Test("A recovery record round-trips so it survives termination")
    func roundTrips() throws {
        let original = record(state: .running)
        let data = try JSONEncoder().encode(original)
        let back = try JSONDecoder().decode(ActiveWorkoutRecovery.self, from: data)
        #expect(back == original)
    }
}
