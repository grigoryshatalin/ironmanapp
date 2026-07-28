# WorkoutKit Mapping — Endurance

How an Endurance session becomes a schedulable Apple Workout, and what
deliberately does not.

Status: **Release 2, Stage 4.** Conversion policy, scheduling coordinator and
settings are implemented and unit-tested. **`WorkoutScheduler` has never run** —
no workout has reached a real Watch. See §8.

---

## 1. Layering

```
EnduranceDomain           WorkoutKitConverter + representations. No WorkoutKit.
      ▲ domain types only
EnduranceWorkoutKit       WorkoutKitSchedulerAdapter, #if canImport(WorkoutKit)
      ▲ WorkoutScheduling protocol
Endurance (app)           WorkoutKitCoordinator, WorkoutKitSettingsView
```

The converter decides *fidelity*; the adapter only builds framework objects. So
every rule below is asserted on the host with no device.

---

## 2. Three outcomes

| Outcome | Meaning | Scheduling |
|---|---|---|
| `exact` | The workout transfers faithfully | Automatic |
| `simplified` | The workout itself differs | **Requires consent** |
| `unsupported` | Cannot be represented | Never scheduled; stays whole in Endurance |

An `unsupported` result carries a stated reason and **no** partial
representation — a half-converted workout is worse than none.

---

## 3. Structural vs supplemental — the key distinction

Not every disclosure is a change to the workout.

**Supplemental** (still `exact`, disclosed but not gating):

| Warning | Why it does not gate |
|---|---|
| `techniqueCuesRemainInEndurance` | Cue text; the Workout app has nowhere to show it |
| `fuelingInstructionsRemainInEndurance` | Guidance, not workout structure |
| `supplementalInstructionsRemainInEndurance` | Gear and safety notes |
| `rpePreservedAsText` | Effort guidance kept as a step name, never fabricated into a sensor alert |

In all four, every interval, goal and target transfers intact. The session
performed on the Watch *is* the planned session.

**Structural** (forces `simplified`, requires consent):

| Warning | What actually changes |
|---|---|
| `stepsCombined` | Steps merged into one |
| `nestedRepetitionsFlattened` | Repeat structure altered |
| `shortenedWorkoutUsesSingleGoal` | Intervals replaced by one time goal |
| `transitionInstructionsOmitted` | Content dropped |
| `drillRepresentedAsWork` | A drill appears as a work interval |

### Why this split exists

It was added in Stage 4 to fix a real defect. The inherited policy treated *any*
disclosure as a simplification. Because 34 of the first 60 bundled sessions carry
technique cues, the measured result was:

```
before:  exact 0   simplified 28   unsupported 32
after:   exact 17  simplified 11   unsupported 32
```

With zero exact conversions, `automaticSchedulingAllowed` was never true — an
athlete could enable the feature and nothing would ever reach their Watch. The
behaviour was technically correct and practically useless.
`BundledPlanConversionTests` now fails if that returns.

---

## 4. Sport and goal mapping

| Endurance sport | WorkoutKit activity |
|---|---|
| Run | `running` |
| Bike | `cycling` |
| Swim | `swimming` |
| Strength | `highIntensityIntervalTraining` — a deliberate approximation, see below |
| Mobility | `functionalStrengthTraining`, or `highIntensityIntervalTraining` if built as a circuit |
| Brick | `SwimBikeRunWorkout` — bike → run container |
| Race | `SwimBikeRunWorkout` — legs read from the session's own main set |
| Recovery | **unsupported** — walking or nothing; no structure worth sending |

### Why strength is filed as HIIT

There is no strength activity WorkoutKit will schedule that also carries
interval structure. The original policy — "no honest equivalent, send nothing" —
meant every strength session in the plan silently never reached the Watch: 39 of
382 sessions, none of them schedulable.

HIIT accepts a time goal and interval blocks, which is structurally what a
strength circuit is, and the Watch renders it as a real workout the athlete can
start and complete. That is worth more than accuracy of the label.

The cost is accepted explicitly: the resulting HealthKit workout is recorded as
HIIT, not strength training. `HealthActivityMapping` therefore maps HIIT
(raw value 63) back to `.strength` on import, so a session completed on the
Watch returns and matches its planned session instead of being dropped as an
unmapped activity type. The same mapping means a HIIT workout the athlete does
independently also files as strength — a consequence of the round trip, not an
oversight.

Mobility and recovery remain unsupported. They carry no interval structure worth
sending, and approximating them would put a workout on someone's wrist that does
not describe what they are doing.

**Export is unchanged**: a strength session logged in Endurance is still written
to HealthKit as `traditionalStrengthTraining`, which is accurate and which the
Fitness app represents properly. Only the Watch-scheduling path approximates.

### Coverage against the real 36-week plan

| Sport | Schedulable / total |
|---|---|
| Run | 141 / 141 |
| Swim | 93 / 93 |
| Bike | 73 / 73 |
| Strength | 39 / 39 |
| Mobility | 35 / 35 |
| Race | 1 / 1 |
| **Total** | **382 / 382** |

Nothing is refused. 205 convert exactly; 177 are simplified and wait for the
athlete's approval of the specific simplification.

### Multisport: bricks and race day

Bricks and races were previously refused outright — 71 sessions, and the most
triathlon-specific work in the plan. `SwimBikeRunWorkout` is purpose-built for
this; the refusal predated using it.

A brick is **two sessions** sharing a `brickGroupID`, so conversion has to see
the group: converting the bike leg alone would put half a session on the Watch
and call it done. The container is owned by the first leg so the group schedules
once. A race is **one session** whose main set already holds swim / T1 / bike /
T2 / run, so its legs come from the steps; our transitions are dropped because
`SwimBikeRunWorkout` inserts its own and passing both would double them.

Multisport is **always `simplified`, never `exact`**. The container carries leg
order and locations and nothing else — no distances, no durations, no intervals.
Those stay in Endurance, which is a real difference from the plan, so it is
disclosed and requires approval rather than being sent silently.

`SwimBikeRunWorkout.supportsActivityOrdering` is asserted against the real
framework for both bike→run and swim→bike→run in `WorkoutKitFrameworkAcceptanceTests`.

### Mobility

Mapped by the shape of the session rather than by sport. A circuit — repeated
work with recovery — behaves like interval training. A continuous flow does not,
and calling a thirty-minute mobility session "high intensity interval training"
would misdescribe it both on the wrist and in Health. Every mobility session in
the bundled plan is a single continuous flow, so all 35 take the functional
strength branch; the interval branch exists for coach-authored circuits (§28.12).

Swim was 58/93 until a plan **data** defect was fixed: a "20 s rest" step carried
`durationSeconds: 0` because the generator helper only accepted whole minutes, so
the duration lived in the label text. A leaf step with no duration, distance or
open goal cannot be converted, and one such step refuses the whole session. Measured by `reportCoverage`, which prints
these numbers on every test run so a policy change shows up as a coverage change.

---

Goals: distance preferred when the plan states one, else planned time, else
open. A pool swim with both distance and time uses the pool goal; open water
does not. An unknown location stays unknown rather than being guessed.

Targets map one-to-one to alerts: heart rate, speed, power, cadence. **An RPE
zone never becomes an alert** — it is preserved as text.

---

## 5. Scheduling policy

- **Off by default.** Authorization is requested only when the athlete enables it.
- **Only an upcoming window** is synchronized — next session, 3, 7 or 14 days.
  Never all 382.
- **Exact schedules automatically; simplified waits for consent**, approved
  against the conversion *fingerprint*, so a later, different simplification of
  the same session needs fresh approval rather than inheriting the old one.
- **Completed, skipped, replaced or moved sessions are removed** from the Watch.
  A stale structured workout on someone's wrist is worse than none.
- A schedule produced by an **older converter version reports `stale`**, not
  `scheduled`.

Known limitation: with the *next session only* horizon, if that session is
unrepresentable (day one of the bundled plan is mobility), nothing is sent. The
settings preview shows the per-session status so this is visible rather than
mysterious.

---

## 6. Identity

`deterministicWorkoutPlanID` derives from the Endurance scheduled-workout ID plus
the conversion version. It is **not** a HealthKit UUID and **not** an execution
ID. A conversion-behaviour change therefore yields a new plan identity rather
than silently managing an obsolete one.

---

## 7. Recovery

The schedule record is written **before** the framework call. If the call
succeeds and the app dies before the local transaction finishes,
`reconcileWithSystem()` compares our records against
`WorkoutScheduler.scheduledWorkouts` on next launch and corrects both directions:
a record stuck at `scheduling` that is live becomes `scheduled`; a record
claiming `scheduled` that the system no longer has becomes `removed`.

---

## 8. Not verified

Everything above rests on unit tests with an injected fake scheduler and a clean
iOS build. **No part of this has touched real WorkoutKit.** Specifically unverified:

- `WorkoutScheduler.requestAuthorization()` and its system prompt.
- Whether a converted plan is accepted by `WorkoutScheduler.schedule(_:at:)`.
- Whether scheduled workouts appear in the Workout app on a paired Watch.
- Whether alerts, goals and interval blocks render as intended.
- Removal and reconciliation against the real system schedule.
- Behaviour when authorization is revoked externally.

See `PHYSICAL_DEVICE_RELEASE_2_CHECKLIST.md`.
