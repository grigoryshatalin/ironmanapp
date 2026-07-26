# HealthKit Architecture — Endurance

How Endurance reads from and writes to HealthKit, and — more importantly — the
cases in which it deliberately refuses to.

Status: **Release 2, Stages 2–3 implemented.** Verified on the iOS 26.5
Simulator and by pure unit tests. **Nothing in this document has been verified
against a real HealthKit store on hardware** — see §10.

---

## 1. Layering

```
  EnduranceDomain          Foundation only. No HealthKit.
    HealthCapability, ExternalWorkoutSummary, WorkoutExecution,
    ImportCursor, HealthCapabilityState, WorkoutMatcher
        ▲
        │  domain types only
        │
  EnduranceHealth          Mixed, by design:
    ├── HealthKit-free (tested on the host, no device):
    │     HealthActivityMapping, HealthCapabilityPlan, HealthImportFilter,
    │     ImportReconciler, ExecutionMerger,
    │     ExportEligibilityEvaluator, HealthExportPayloadBuilder,
    │     HealthOwnership
    └── #if canImport(HealthKit):
          HealthKitWorkoutImporter, HealthKitWorkoutExporter
        ▲
        │  protocols: HealthWorkoutImporting, HealthExporting
        │
  Endurance (app)
    HealthCoordinator (import), HealthExportCoordinator (export),
    HealthSettingsView, HealthInboxView, SwiftData records
```

The split inside `EnduranceHealth` is the important part. Every decision that
could corrupt the athlete's record — is this a duplicate, may this be exported,
is this the same execution — lives in the HealthKit-free half, so it runs under
`swift test` on any machine. The framework half only translates.

---

## 2. Types requested

### Read (Stage 2)

Requested together when the athlete taps **Connect Health**, and only these:

| Type | Why |
|---|---|
| `HKObjectType.workoutType()` | Match finished sessions to the plan |
| `heartRate` | Show the effort actually held |
| `distanceWalkingRunning` | Fill in run distance |
| `distanceCycling` | Fill in ride distance |
| `distanceSwimming` | Fill in swim distance |
| `activeEnergyBurned` | Weekly summary |

**Deliberately not requested:** `restingHeartRate`, `heartRateVariabilitySDNN`,
`cyclingPower`, `runningPower`, `workoutRoute`, sleep, and everything else.
They are modelled in `HealthCapability` but not in `HealthCapabilityPlan.coreImport`,
because no visible feature uses them yet and §C forbids requesting permissions
"for future use".

### Write (Stage 3)

Requested only when the athlete enables **Save my logged workouts to Health** —
never at launch, and never bundled with the read request:

| Type | Why |
|---|---|
| `HKObjectType.workoutType()` | The workout itself |
| `activeEnergyBurned` | Only when a real value exists |
| `distanceWalkingRunning` / `distanceCycling` / `distanceSwimming` | Only when a real distance exists |

Endurance never requests write access to heart rate, power, or routes, because
it never has genuine values for them.

---

## 3. Authorization model

`authorizationStatus(for:)` reports **share (write) authorization only**.
HealthKit deliberately cannot tell an app whether reads were granted — that is
how it keeps a withheld category invisible.

Endurance therefore models authorization **per capability, per access**, and read
capabilities resolve to `.unknowable` once asked. There is no global
"HealthKit authorized" boolean anywhere in the codebase, and a test asserts we
never report `.authorized` for a read. The UI says **"Connected"**, never
"Authorized".

Write status *is* knowable and is reported honestly: `Ready to save`,
`Permission needed`, `Partially available`, `Saving unavailable`, `Off`.

---

## 4. Import (Stage 2)

`HKAnchoredObjectQuery` over `workoutType()`, with the anchor archived into
`SDHealthImportCursor`. The store is never rescanned.

Each `HKWorkout` maps through `HealthActivityMapping`, a **closed** table. An
unmapped activity type is skipped, never guessed — so a yoga session cannot
arrive as a threshold run.

Only metrics HealthKit actually provides are carried. Averages come from
`workout.statistics(for:)`; nothing is derived, inferred, or defaulted.

`ImportReconciler` then classifies each activity as new, updated, deleted,
self-authored, too short, or unchanged.

---

## 5. Export eligibility (Stage 3)

Twelve states, decided by `ExportEligibilityEvaluator` — a pure function. Views
render the result; they never compute it.

| State | Meaning |
|---|---|
| `eligible` | May be written now |
| `alreadyExported` | Has a HealthKit UUID already |
| `importedFromHealthKit` | Came from Health; writing back would duplicate |
| `externallyOwned` | Watch or another app owns the record |
| `unsupportedSport` | No honest single-activity mapping |
| `unsupportedMultisport` | Brick or race — see below |
| `missingRequiredData` | Not completed, no start, zero/negative duration |
| `permissionRequired` | Write access not granted |
| `exportDisabled` | Athlete turned export off |
| `currentlySaving` | A save is in flight |
| `failedRetryable` | Worth retrying |
| `failedPermanent` | Will not improve on retry |

**Evaluation order is deliberate:** structural validity → provenance → already
exported → representability → preferences and permission. Provenance is checked
*before* settings so the athlete is never told "enable export" for a workout that
enabling export still would not — and must not — write.

**Brick and race** return `unsupportedMultisport`. They are genuinely multisport;
filing one as a single ride would misrepresent the session. Stage 3 refuses
honestly and keeps the full session in Endurance. WorkoutKit (Stage 4) will
introduce the correct representation.

---

## 6. What is written

`HealthWorkoutExportPayload` is built and asserted before any HealthKit object
exists. It has **nowhere to put** fabricated data — absence is represented by
absence, never a plausible zero.

Written when genuinely known: activity type, start, end, duration, distance,
active energy, indoor/outdoor, pool/open-water.

Never written: heart rate, power, cadence, pace samples, routes, or any
sensor measurement Endurance did not receive.

### Metadata

| Key | Purpose |
|---|---|
| `HKMetadataKeyWasUserEntered` | Distinguishes a hand-logged session from a recording |
| `HKMetadataKeyIndoorWorkout` | When known |
| `HKMetadataKeySwimmingLocationType` | Pool vs open water |
| `com.example.endurance.executionID` | **Orphan recovery** — see §8 |
| `com.example.endurance.scheduledWorkoutID` | Link to the plan |
| `com.example.endurance.idempotencyKey` | Duplicate prevention |
| `com.example.endurance.exportVersion` | Payload shape version |
| `com.example.endurance.schemaVersion` | App schema version |

Endurance uses `HKWorkoutBuilder`, not the `HKWorkout` initialisers, which Apple
deprecated in iOS 17. The builder also matches the "never fabricate" rule
structurally: a session with no distance simply adds no distance sample.

---

## 7. Duplicate prevention

The failure this prevents: **one physical session appearing as two completed
workouts** because two Apple frameworks reported it.

Idempotency key: `endurance.export.<executionID>` — derived from identity only.
A retitled or rescheduled workout keeps the same key; a double tap collides.

| Pathway | Defence |
|---|---|
| Our export returns via anchored import | `sourceBundleIdentifier == our bundle` → skipped |
| Watch saves to Health *and* syncs completion | `ExecutionMerger` attaches on shared external key |
| Manual completion, then a matching import | Merger attaches rather than inserting |
| Anchored query re-delivers after relaunch | Revision/field comparison → `unchanged` |
| Rapid double tap / intent racing UI | `inFlight` set + `currentlySaving` state |
| Retry after failure | Existing record consulted before saving |
| Already exported | `exportedProviderID` short-circuits |

---

## 8. Orphan recovery

The hard case: HealthKit accepts the save, then local persistence fails.

1. A `pending` export record is written **before** the save.
2. On success, the returned UUID is stored and the record becomes `saved`.
3. If persistence fails, the record stays `pending` with no provider id —
   `isPotentialOrphan`.
4. On next launch, `recoverOrphanedExports()` queries HealthKit by the
   `executionID` metadata key and reconnects it.

Without step 4, a successful save would become invisible: Endurance could
neither show it nor avoid exporting it again.

---

## 9. Editing, deletion, disconnect

**HealthKit samples are immutable.** An edit is delete + save.

- Local-only fields (notes, RPE, fatigue, soreness) never touch HealthKit.
- Represented fields (duration, distance, sport, start) require replacement and
  **explicit confirmation**, because a visible Health record changes.
- Replacement saves the new record **first**, then deletes the old one. A failure
  therefore leaves a visible duplicate — recoverable — rather than a hole.
- `healthSaveFailedAfterDelete` is modelled explicitly and flagged for recovery.

**Ownership** is checked before any delete, twice: against our own export record
(`isEnduranceOwned`), and against `sourceRevision.source.bundleIdentifier` in
HealthKit itself. Endurance never deletes a workout created by Apple, Garmin,
Strava, or any other app.

**Disconnect** stops import and export and clears Endurance's local integration
records. It does **not** delete anything from Apple Health, and it does not erase
training history. Removing local connection records is a separate, explicit
action.

---

## 10. What is NOT verified

Everything above is verified by unit tests and a clean iOS build. The following
require a physical iPhone and are **not** claimed:

- A real `HKHealthStore` accepting a write.
- The system authorization sheet and its copy.
- Anchored-query behaviour against a populated store.
- Whether a written workout appears correctly in the Health app.
- Round-trip de-duplication against real HealthKit UUIDs.
- Deletion of an Endurance-owned workout in the real store.
- Behaviour when authorization is changed outside the app.

The simulator additionally reports
`Missing com.apple.developer.healthkit entitlement` during test runs, because
tests build with `CODE_SIGNING_ALLOWED=NO`. This does not affect the fake-backed
tests, but it does mean **no simulator run has exercised the real HealthKit
path**.

See `PHYSICAL_DEVICE_RELEASE_2_CHECKLIST.md`.
