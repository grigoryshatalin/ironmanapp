# DATA_SCHEMA.md — Endurance

The finalized data schema, **as implemented** in `EndurancePackages/Sources/
EnduranceDomain`. Two halves, deliberately separated (brief §15):

- **Immutable plan content** — decoded from bundled JSON, never mutated at
  runtime. Types under `Plan/`.
- **Mutable athlete state** — persisted via SwiftData, exported/imported as JSON.
  Types under `State/`.

`schemaVersion` is currently **1**. `PlanValidator` rejects unsupported or
malformed content with located, actionable errors.

---

## A. Immutable plan content

### `TrainingPlanDefinition`
| field | type | notes |
|---|---|---|
| `id` | UUID | stable plan id |
| `schemaVersion` | Int | ≤ app's supported version |
| `name`, `summary` | String | |
| `durationWeeks` | Int | must equal `weeks.count` |
| `startWeekday` | Int | Gregorian 1–7 (Mon = 2). Weeks begin on this weekday. |
| `phases` | `[TrainingPhaseDefinition]` | must tile weeks 1…N with no gaps/overlaps |
| `weeks` | `[TrainingWeekDefinition]` | |
| `metadata` | `PlanMetadata` | author, version, level, goal, disclaimer, tags |

Carries **no absolute dates** — `ScheduleEngine` maps day indices onto real
dates. Helpers: `totalDays`, `allDays`, `phase(forWeek:)`.

### `TrainingPhaseDefinition`
`id`, `name`, `startWeek`, `endWeek`, `objective`, `defaultLoad: WeekLoad`.

### `TrainingWeekDefinition`
`id`, `weekNumber` (1‑based), `phaseID`, `title`, `objective`,
`load: WeekLoad` (`base|build|recovery|peak|taper|race`), `plannedMinutes`,
`days: [TrainingDayDefinition]`, `coachNote?`.
`WeekLoad.acceptsRestoredVolume` is `false` for recovery/taper/race — the hook
for the "don't restore missed volume into a recovery week" safety rule.

### `TrainingDayDefinition`
`id`, `dayIndex` (global 0‑based = `(weekNumber−1)*7 + weekdayOffset`),
`weekdayOffset` (0–6 within the week), `title`, `objective`,
`workouts: [WorkoutTemplate]`, `nutrition: DayNutrition?`,
`recovery: RecoveryGuidance?`, `notes?`. Computed `isRestDay`.

### `WorkoutTemplate`
`id`, `sport: Sport`, `title`, `objective`, `plannedDurationMinutes`,
`plannedDistanceMeters?`, `intensity: IntensityZone`,
`stressCategory: StressCategory`, `order`, `preferredHour?`, `preferredMinute?`,
`warmup/mainSet/cooldown: [WorkoutStep]`, `techniqueCues: [String]`,
`fueling: FuelingGuidance?`, `hydration: HydrationGuidance?`, `gear: [String]`,
`safetyNotes: [String]`, `isBrick`, `brickGroupID?`, `isOptional`.

### `WorkoutStep` (recursive — renders the interval layout, not a text wall)
`id`, `kind: StepKind` (`warmup|work|recovery|steady|cooldown|drill|transition|
rest`), `label`, `durationSeconds?`, `distanceMeters?`, `isOpenGoal`,
`intensity?`, `repeats`, `childSteps: [WorkoutStep]`, `note?`. A node with
`repeats > 1` + `childSteps` is a repeat block, e.g. `4 × (6′ Z3 + 3′ easy)`.
`expandedDurationSeconds` sums repeats/children.

### Enums (portable, sensor‑independent)
- `Sport`: `swim|bike|run|strength|mobility|recovery|brick|race` — each exposes a
  `localizationKey`, `preferredSymbolName` + `fallbackSymbolName` (SF Symbol
  availability), and an `accentToken`.
- `IntensityZone`: `recovery|endurance|tempo|threshold|vo2|variable|raceEffort`,
  with `rpeRange` (1–10 fallback) and `zoneShorthand` ("Z2"…).
- `StressCategory`: `recovery|easy|moderate|hard|long|raceSpecific`, with
  `relativeLoad` and `isHighStress` (drives conflict rules).

### Nutrition / recovery (configurable targets, never prescriptions)
`FuelingGuidance` (carb g/h low/high, note, `isKeyFuelingSession`),
`HydrationGuidance` (fluid mL/h low/high, note), `DayNutrition`,
`RecoveryGuidance`.

---

## B. Mutable athlete state

### `ScheduledWorkout` (the unit Today/Plan/Progress/Notifications operate on)
Identity: `identity: WorkoutIdentity` (`id` == `scheduledWorkoutID`).
Position: `weekNumber`, `weekdayOffset`, `dayIndex`, `order`.
Denormalized planned essentials (from the template): `sport`, `title`,
`objective`, `plannedDurationMinutes`, `plannedDistanceMeters?`, `intensity`,
`stressCategory`, `isBrick`, `brickGroupID?`, `isOptional`.
Scheduling: `originalDate` (never changes), `scheduledDate`, `plannedStart`.
State: `status: WorkoutStatus`, `completion: WorkoutCompletion?`,
`modifications: [PlanModification]`, `notificationIDs: [String]`,
`reducedDurationMinutes?`. Computed: `effectivePlannedMinutes`, `wasMoved`.

> Denormalizing the planned essentials lets progress, notifications, conflict
> rules, widgets, and the watch app run against the schedule alone.

### `WorkoutStatus`
`planned|inProgress|completed|partiallyCompleted|skipped|rescheduled|replaced`,
each with `preferredSymbolName`+`fallbackSymbolName`, `countsAsDone`,
`shouldCancelReminders`.

### `WorkoutCompletion`
`completedAt`, `actualDurationMinutes?`, `actualDistanceMeters?`,
`averageHeartRate?`, `averagePower?`, `perceivedExertion?` (1–10), `fatigue?`
(1–5), `soreness?` (1–5), `notes?`, `source: CompletionSource`
(`manual|appTimer|healthKit|appleWatch|external`).

### `PlanModification` (audit trail)
`id`, `type: ModificationType` (`reschedule|shorten|replaceWithRecovery|skip|
restore|note|adaptation`), `createdAt`, `oldDate?`, `newDate?`,
`oldDurationMinutes?`, `newDurationMinutes?`, `reason?`.

### `WorkoutIdentity` (survives reschedule/sync/import/re‑export — brief §28.2)
`planID?`, `templateID?`, `scheduledWorkoutID`, `executionID?`,
`externalReferences: [ExternalWorkoutReference]`. Separate ids per concern;
never title+date. `ExternalWorkoutReference`: `provider: FitnessProviderID`,
`providerActivityID`, `importedAt`, `lastSyncedAt?`, `sourceRevision?`.

### Configuration
- `ScheduleConfiguration`: `anchor: PlanAnchor` (`.startDate`/`.raceDate`),
  `startWeekday`, `weekdayDefaultTime`/`weekendDefaultTime: TimeOfDay`,
  `timeZoneIdentifier?`, and (recorded for the future day‑rotation transform)
  `preferredLongBikeWeekday?`/`preferredLongRunWeekday?`/`preferredRestWeekday?`.
- `NotificationPreferences`: `enabledCategories: Set<NotificationCategory>`,
  per‑category times/leads, `schedulingWindowDays`.
- `TimeOfDay`: `hour`, `minute` (components, never absolute seconds).

### Extension snapshot
`SharedTodaySnapshot` — a compact `Codable` "today" for widgets/intents/watch,
read from the App Group container instead of opening the full store (brief §28.19).

---

## C. Export format

`TrainingHistoryExport` (JSON, ISO‑8601 dates, pretty + sorted keys):
`schemaVersion`, `exportedAt`, `planID?`, `scheduleConfiguration`,
`notificationPreferences`, `units`, `scheduledWorkouts`. Round‑trips exactly
(tested). `ExportService.completionCSV` additionally emits an escaped CSV of
completed/skipped sessions.

---

## D. Deterministic identity

Regeneration must reconcile to the **same** instances, never duplicate. The
`scheduledWorkoutID` is a **name‑based UUIDv5** of `planID:templateID:dayIndex`
(RFC 4122 §4.3, SHA‑1; validated against the standard DNS test vector). Same
plan + same day → same id across regenerations, devices, and export/import.


---

# Release 2 — Schema version 2

Additive only. No Release 1 entity gains, loses, renames or retypes a property,
so `MigrationStage.lightweight` applies and nothing is rewritten.
`MigrationTests` proves this against a real on-disk V1 store.

## Entities added

| Entity | Purpose |
|---|---|
| `SDExternalWorkoutRecord` | One activity observed from a provider |
| `SDWorkoutExecution` | A performance of a session, however observed |
| `SDWorkoutMatchDecision` | The athlete's decision, so suggestions do not return |
| `SDHealthImportCursor` | Opaque anchored-query anchor, per provider |
| `SDHealthAuthorizationState` | Per-capability, per-access authorization |
| `SDHealthExportRecord` | Export status, idempotency key, provider reference, ownership |
| `SDWorkoutKitScheduleRecord` | Stage 4 (declared, unused) |
| `SDWatchSyncRecord` | Stage 6 (declared, unused) |
| `SDActiveWorkoutRecovery` | Stage 5 (declared, unused) |
| `SDIntegrationErrorRecord` | Non-sensitive integration failure codes |

## CloudKit forward-compatibility

Every Release 2 property is optional or defaulted, and none uses `.unique` —
CloudKit supports neither.

**Open issue:** the two Release 1 entities (`SDScheduledWorkout`,
`SDAppSettings`) still use `@Attribute(.unique)`. Dropping a unique constraint is
itself a migration, so this must be done deliberately in a future schema version
**before** CloudKit sync is enabled — not discovered when someone turns it on.

## Versioning rule

Schema v2 has not shipped, so entities may still be added to it. **Once v2
ships, adding an entity requires v3.** A stale v2 store fails with
`Cannot use staged migration with an unknown model version`; the app degrades to
an ephemeral store and leaves the file intact rather than crashing.

## Identity

Unchanged. `WorkoutIdentity` remains authoritative; HealthKit UUIDs, WorkoutKit
identifiers and watch session ids are **references**, never primary identity.
`deterministicScheduledID` still derives from the plan's canonical day index.
