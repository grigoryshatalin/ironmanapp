# Release 2 — Verification Report

Branch: `release/2-apple-ecosystem`
Toolchain: Xcode 26.6 (17F113) · iOS 26.5 SDK · watchOS 26.5 SDK · Swift 6.3.1,
Swift 6 language mode, `SWIFT_STRICT_CONCURRENCY: complete`

> **Release 2 is in progress: 3 of 9 stages complete.** Stages 4–9 (WorkoutKit,
> active workout, watchOS, Live Activities, widgets, App Intents, full-system
> verification) are not implemented.
>
> **No HealthKit behaviour has been verified against a real health store.** The
> adapters compile for iOS and every decision around them is unit-tested with
> injected fakes, but simulator test builds have no HealthKit entitlement, so the
> real read/write path has never executed.

---

## 1. Baseline and current test counts

Recorded per §A before any Release 2 production code was written.

| Suite | Release 1 baseline | After Stage 3 |
|---|---|---|
| Domain + health packages (`swift test`) | 69 | **174** |
| App unit tests | 4 | **41** |
| UI acceptance | 7 | 7 |
| Accessibility matrix | 9 | 9 |
| Screenshot capture | 9 | 9 |
| **App target total** | **29** | **66** |
| Warnings (clean `build-for-testing`, **all targets**) | 0 | **0** |

> **Correction.** An earlier Stage 3 report claimed zero warnings on the basis of
> `xcodebuild build`, which compiles the **app target only**. A full
> `build-for-testing` then surfaced **31** strict-concurrency warnings in the
> test targets — `XCTestCase`'s throwing `setUp`/`tearDown` are nonisolated and
> were mutating main-actor state. Converted to the `async` variants, which
> inherit the class's `@MainActor` isolation. This is the second time in this
> project that an incomplete build produced a misleading warning count; read
> build hygiene from `build-for-testing`, never from `build`.

New in Stage 3: 45 pure tests (eligibility, payload, ownership) and 18 app tests
(export workflow, idempotency, orphan recovery, deletion, round trip).

## 2. Test commands

```sh
# Domain + EnduranceHealth — no device, no entitlement, no simulator
cd EndurancePackages && swift test

# App: unit + UI + accessibility + screenshots
xcodebuild test -project Endurance.xcodeproj -scheme Endurance \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

# Build hygiene — read from a FULL build, never an incremental one
xcodebuild build-for-testing -project Endurance.xcodeproj -scheme Endurance \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

---

## 3. Stage status

| Stage | State |
|---|---|
| 1. Baseline, schema v2, migration | ✅ complete, committed |
| 2. HealthKit read | ✅ complete, committed |
| 3. HealthKit write | ✅ complete, committed |
| 4. WorkoutKit | ⛔ not started |
| 5. Active workout | ◐ state machine + monotonic clock only |
| 6. Apple Watch | ⛔ not started |
| 7. Live Activities | ⛔ not started |
| 8. Widgets, App Intents | ⛔ not started |
| 9. Full-system verification | ⛔ not started |

---

## 4. Migration

**No schema bump beyond v2.** `SDHealthExportRecord` is additive within v2,
which has not shipped.

Verified against a **real on-disk Release 1 store**, not a synthetic one:

- Every scheduled workout survives (382).
- Completion notes, duration and RPE survive.
- A reschedule keeps its modification audit trail.
- Settings and preferred training days survive.
- Deterministic identifiers are unchanged.
- Repeated migration is idempotent.
- New entities exist and start empty.
- A fresh install still opens.

**Rule recorded:** once v2 ships, adding an entity requires v3. A stale v2 store
fails with `Cannot use staged migration with an unknown model version`; the app
degrades to an ephemeral store and leaves the file intact.

---

## 5. Defects found by the new tests

1. **`export()` reported `currentlySaving` for a completed save.** `defer` runs
   *after* the return value is computed, so the in-flight set still contained the
   execution when the reported state was read. Now cleared explicitly first.
2. Earlier in Release 2: Xcode compiled a **cached copy of the local package**,
   so new domain types were invisible while old ones resolved. Clearing
   DerivedData fixed it — worth knowing when adding files to `EndurancePackages`.

---

## 6. What is verified, and how

| Claim | Evidence |
|---|---|
| Release 1 data migrates without loss | ✅ unit, real on-disk V1 store |
| Import is incremental and idempotent | ✅ unit, fake importer |
| Our own exports never return as imports | ✅ unit |
| Watch + Health double-report collapses to one execution | ✅ unit |
| Matching never auto-matches on sport + day | ✅ unit |
| Imported workouts are never re-exported | ✅ unit |
| Bricks and races are refused honestly | ✅ unit |
| One execution never writes twice | ✅ unit, incl. concurrent attempts |
| A failed save keeps the local completion | ✅ unit |
| An orphaned export is recovered via metadata | ✅ unit |
| Endurance never deletes another app's workout | ✅ unit |
| Disconnect preserves training history | ✅ unit |
| HealthKit adapters compile for iOS | ✅ clean build, 0 warnings |
| Release 1 behaviour is unchanged | ✅ full suite |
| **Any real HealthKit read or write** | ⛔ **not verified — needs hardware** |

---

## 7. Remaining hardware verification

See `PHYSICAL_DEVICE_RELEASE_2_CHECKLIST.md`. In summary:

- **The Release 1 notification gate is still open** and remains mandatory before
  any public distribution.
- No real HealthKit authorization sheet has been shown.
- No workout has been written to or read from a real health store.
- Simulator test builds omit the entitlement entirely
  (`Missing com.apple.developer.healthkit entitlement` appears in the log).

---

## 8. Deviations from the specification

| Spec | Actual | Why |
|---|---|---|
| "HealthKit authorized" state | Per-capability, with `.unknowable` for reads | HealthKit cannot report read authorization; a boolean would be a guess |
| `HKWorkout` construction | `HKWorkoutBuilder` | `HKWorkout` initialisers deprecated in iOS 17 |
| Export a brick/race | Refused as `unsupportedMultisport` | Explicitly allowed by §1 for Stage 3 |
| Editing an exported workout | Modelled and tested; no edit UI yet | Endurance has no post-completion edit surface to attach it to |

---

## 9. Recommendation

**Stage 4 (WorkoutKit) may begin.** Stage 3 is complete against its definition of
done for everything achievable without hardware: eligibility, payload,
idempotency, ownership, orphan recovery, settings, completion integration,
localization, tests and documentation.

Two caveats that are not blockers for Stage 4 but *are* blockers for release:

1. Every HealthKit claim rests on injected fakes. The first device run should be
   treated as genuine discovery, not confirmation.
2. The Release 1 notification gate remains unclosed.
