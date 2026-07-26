# Release 2 Implementation Plan

Release 2 is delivered as independently verifiable stages. This document records
the implementation plan before production changes land, so framework limitations
are explicit rather than hidden in view code.

## Stage 4 — WorkoutKit conversion and scheduling

### API facts verified against Xcode 26.6 / iOS 26.5 SDK

- `WorkoutScheduler` is available from iOS 17 / watchOS 10. It exposes
  `authorizationState`, `requestAuthorization()`, `schedule(_:at:)`,
  `remove(_:at:)`, `scheduledWorkouts`, `removeAllWorkouts()`, and an
  app-specific maximum scheduled-workout count.
- `WorkoutPlan` has an app-supplied UUID and serializable data representation.
  The scheduler does not return a per-operation identifier. Endurance will use
  a deterministic `WorkoutPlan.id` derived from its scheduled-workout ID and
  conversion version, and reconcile it against `scheduledWorkouts`.
- `SingleGoalWorkout` supports open, time, distance, energy, and (on iOS 18 /
  watchOS 11) pool-distance-with-time goals. `CustomWorkout` supports one
  warmup, repeatable work/recovery blocks, and one cooldown.
- `CustomWorkout` and `SingleGoalWorkout` provide `supportsActivity`,
  `supportsGoal`, and (for custom) `supportsAlert`; the adapter checks these
  before invoking the scheduler.
- WorkoutKit offers numeric heart-rate, speed, power, and cadence alerts. It
  has no direct pace alert; pace is represented as a speed range.
- `SwimBikeRunWorkout` represents an ordered sequence of swimming, cycling,
  and running activities, but it has no transitions, per-leg goals, or
  structured steps. It cannot faithfully carry Endurance's full race plan.

### Design

1. Replace the Stage 1 placeholder conversion with Foundation-only, Codable
   representations and a pure converter in `EnduranceDomain`. The result always
   contains the stable scheduled and template identities, source sport,
   conversion version, outcome, representation (when schedulable), warning and
   unsupported-element keys, confirmation requirement, and automatic-scheduling
   eligibility. `nil` never means unsupported.
2. Map simple swim/bike/run sessions conservatively. Empty structures become
   a single goal; one warmup/one cooldown and work/recovery interval blocks map
   exactly; RPE is retained in a custom step display name but never fabricated
   into a sensor alert. Technique, equipment, fueling, free-form notes, nested
   repetitions, and free-form transitions are simplified only with disclosure.
3. Refuse strength, mobility, recovery, explicit brick containers, and the
   bundled full triathlon race unless the model genuinely contains independently
   schedulable legs. Stage 4 will not file a brick or race as a single ride or
   run. A later plan-model extension can create explicitly linked component
   sessions; no synthetic components are invented from a title.
4. Add a separate `EnduranceWorkoutKit` target for the framework adapter. It
   imports `WorkoutKit` only behind `#if canImport(WorkoutKit)` and converts the
   pure representation to framework values. It uses a deterministic plan UUID
   and queries the app-owned schedule for duplicate prevention/reconciliation.
5. Persist scheduling state separately from conversion state in the existing
   v2 `SDWorkoutKitScheduleRecord`. A pre-schedule journal is saved before the
   framework call; after a persistence failure, a later reconciliation recovers
   the entry by deterministic plan UUID. No schema bump is needed because v2
   has not shipped and this entity was explicitly reserved for Stage 4.
6. Add a main-actor coordinator and store gateway. It schedules an explicit
   workout or synchronizes a conservative configurable horizon (off, next,
   3/7/14 days). It skips unsupported workouts, requires approval for simplified
   work, removes obsolete future plans, never removes historical records, and
   handles reschedule/shorten/replace/skip/complete/anchor changes idempotently.
7. Add a Settings destination and workout-detail section with localized status,
   preview, approval, schedule/remove/retry actions, accessibility identifiers,
   and calm error states. The original Endurance detail remains available in all
   conversion states.
8. Cover pure mapping and coordinator decisions with package/app tests using a
   fake adapter. Compile the real adapter for iOS. Simulator tests demonstrate
   UI and fake-backed logic only; physical iPhone + paired Watch checks remain
   open.

### Completion criteria

- All supported and refused shapes are documented in `WORKOUTKIT_MAPPING.md`.
- Conversion, scheduling, persistence recovery, and synchronization are
  idempotent and tested independently of a Watch.
- The full `build-for-testing`, app tests, accessibility tests, and screenshots
  run serially. No hardware scheduling claim is made until observed on a paired
  device.
