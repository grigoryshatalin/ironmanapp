# Changelog — Endurance

All notable changes to this project. The project is built through defined,
testable stages; each entry records what was added and verified.

The format is loosely [Keep a Changelog](https://keepachangelog.com/). Dates are
absolute.

## [Unreleased] — Release 2 (Apple ecosystem) in progress

### 2026‑07‑27 — Device verification: five defects only hardware could expose

Every item here was found by running the app on a physical iPhone. None was
caught by 291 passing tests, and each is recorded with the reason it was
invisible.

Fixed
- **Read authorization was never requested.** `refreshConnectionState()` derived
  "have we asked?" from `capabilityStates.contains { $0.status != .notDetermined }`.
  Read capabilities always report `.unknowable` (HealthKit will not disclose read
  authorization), so the test was true on first launch, `.notConnected` was
  unreachable, the Connect button never rendered, and `connect()` — the only
  caller of `requestAuthorization` — could never run. HealthKit returns an empty
  array with **no error** when reads are unauthorized, so this presented as an
  empty Health Inbox with a successful import. Whether we have prompted is now
  persisted by us. Diagnosed from the athlete's observation that iOS Settings
  showed a write section but no read section for Endurance.
- **Integration toggles were never persisted.** Health import/export, auto‑export
  and WorkoutKit scheduling lived in memory, so every launch silently reset them
  to off. Because `runImport()` and `rescanFromScratch()` both guard on the
  import toggle, the feature presented as broken rather than disabled. Now stored
  in `UserDefaults` — deliberately device‑local, since they gate a per‑device
  permission and a paired Watch, neither of which syncs.
- **Preferred weekdays were shifted for any non‑Monday start.** `WeekdayLayout`
  derived offsets from `config.startWeekday` (nominal, hardcoded to Monday by
  onboarding) rather than the weekday plan day 0 actually falls on. Every one of
  the twelve existing tests used a Monday start; the helper was named
  `mondayStart`. Race‑date‑anchored plans, which count back onto an arbitrary
  weekday, were always wrong.
- **Tapping a notification crashed the app.** The `UNUserNotificationCenterDelegate`
  methods were marked `nonisolated` to satisfy non‑`Sendable` diagnostics. That
  compiled cleanly and aborted on device with "Call must be made on main thread".
  Now `@preconcurrency` on the conformance, keeping the work where the framework
  requires it.
- **Deliberate short sessions were discarded in silence.** The import floor was
  five minutes; a logged 1‑minute core session vanished with no explanation.
  Lowered to 30 seconds, and anything filtered is now reported rather than
  dropped invisibly.

Added
- `HealthImportBatch.rawSampleCount` / `unmappedSampleCount`, surfaced in Health
  settings. An unauthorized read and an empty store are indistinguishable to the
  API, so the raw count is the only way to tell them apart — a full rescan
  returning zero now names the cause and the Settings path to fix it.
- `rescanFromScratch()` — drops the anchor and re‑reads the whole store,
  preserving match decisions. Required because filtering happens *after* the
  anchored query advances its anchor, so a policy change cannot otherwise
  recover previously discarded activities.
- A debug "send a test notification" action that builds its payload through the
  production path, so it exercises the real tap‑handling code.

Changed
- `testEnablingRequestsAuthorizationAndSynchronizes` was weekday‑dependent: it
  enabled with the `.nextWorkout` horizon, and day one of the bundled plan is
  mobility, which WorkoutKit cannot represent. It passed or failed according to
  the calendar. Confirmed pre‑existing by rerunning against a stashed tree.

### 2026‑07‑26 — Release 2 Stage 3: HealthKit write / export

A complete, idempotent export workflow — not a call to `save`.

Added
- **Export eligibility** as a pure, twelve‑state decision
  (`ExportEligibilityEvaluator`). Views render it; they never compute it.
  Evaluation order puts provenance *before* preferences, so the athlete is never
  told "enable export" for a workout that enabling export still would not write.
- **`HealthWorkoutExportPayload`** — decided and asserted before any HealthKit
  object exists. It has nowhere to put fabricated data: absence is absence, not
  a plausible zero.
- **`HealthKitWorkoutExporter`** using `HKWorkoutBuilder` (the `HKWorkout`
  initialisers are deprecated as of iOS 17). Save, replace, delete, and
  metadata‑based orphan lookup.
- **`HealthExportCoordinator`** — persists a pending record *before* the save,
  so a crash between HealthKit accepting a write and our storing the identifier
  leaves a recoverable row rather than an invisible orphan.
- **Ownership guard** (`HealthOwnership`) checked twice — against our own record
  and against HealthKit's source — so Endurance can never delete another app's
  workout.
- Export settings states, completion‑flow integration, `SDHealthExportRecord`,
  and 45 new localized strings.

Refused, deliberately and with tests
- Re‑exporting a workout imported from Health.
- Re‑exporting a watch‑recorded execution.
- Filing a brick or a race as one misleading single‑sport workout.
- Writing twice for one execution, however the second attempt arrives.

Fixed
- **A real bug the new tests caught:** `export()` reported `currentlySaving` for
  a save that had already finished, because `defer` runs *after* the return
  value is computed. The in‑flight set is now cleared before the state is read.

Migration
- No new schema version. `SDHealthExportRecord` is additive within v2, which has
  not shipped. Once v2 ships, adding an entity requires v3.

### 2026‑07‑26 — Release 2 Stage 2: HealthKit read integration

See commit `be2f0b6`.

### 2026‑07‑26 — Release 2 Stage 1: domain model, schema v2, verified migration

See commits `e2db973`, `cdfeb21`.

## [Released to branch] — Release 1 (Core training MVP)

### 2026‑07‑26 — Release 1 verification & refinement pass

Full results in `RELEASE_1_VERIFICATION.md`. Release 1 is **not** signed off:
on‑device notification verification is outstanding (no physical iPhone
connected). Everything else in the pass is implemented and verified.

Fixed — real defects, not polish
- **Onboarding collected preferred long‑ride / long‑run / rest days and ignored
  them.** Now applied by the new `WeekdayLayout`, which permutes *whole days*
  within each week so a brick run stays with its ride and recovery stays after
  the long run. Roles are derived from plan content, not hard‑coded weekdays, so
  imported coach plans with a different rhythm transform correctly.
- **Changing the start date silently discarded those preferences** — the config
  was rebuilt from scratch instead of carried forward.
- **Today was unusable at the largest Dynamic Type**: the header filled the
  screen and pushed every session off it. Caught by the new accessibility
  matrix, then fixed.
- **The completion sheet ignored the athlete's units**, storing metric distance
  regardless of the chosen system.
- **Container‑level accessibility identifiers erased every descendant's** — a
  SwiftUI behaviour that left exactly one queryable button in the whole tree.
- **False precision**: planned rides read `30.35 km`; now one decimal.

Added
- **Deterministic UI acceptance suite (7 tests)** replacing two permissive smoke
  tests that could not fail for any product reason. Covers onboarding → 382
  scheduled sessions → Today's date → completion → relaunch → reschedule →
  relaunch → anchor change → export round trip.
- **Accessibility matrix (9 tests)**: Light/Dark, Reduce Motion, Increased
  Contrast, Differentiate Without Color, Bold Text, smallest/largest Dynamic
  Type, VoiceOver labelling. Plus acceptance runs on iPhone 17e (small) and
  17 Pro Max (large).
- **79 accessibility identifiers** shared verbatim between app and UI tests, so
  tests never match on localizable English.
- **String Catalog** (`Localizable.xcstrings`, 63 seeded keys) with
  `SWIFT_EMIT_LOC_STRINGS`; domain enums resolve display names through it.
- **Plan filtering** (sport + completed/missed/modified) and **optional interval
  check‑off**.
- **Haptics** on completion, reschedule and export via `sensoryFeedback`.
- **App icon artwork**, generated reproducibly by `Tools/GenerateAppIcon.swift`.
- **13 screenshots**, regenerated by `Tools/capture-screenshots.sh`.
- 12 new domain tests for the day‑layout transform (**69 total**).

Changed — visual refinement
- Today's header, weekly progress and status merged into **one** grouped
  section; the status now sits in the section footer.
- Metadata pills replaced by a single wrapping `MetricLine`
  ("1 hr 15 min · 29 mi · Zone 3") so duration, distance and zone can never be
  truncated.
- Sport symbols standardized: one scaled frame, rendering mode, weight,
  alignment, accessibility label, and SF Symbol fallback.
- Hard‑coded `.green` / `.purple` status tints replaced with semantic colors;
  status is always carried by symbol and wording, never color alone.
- Onboarding's footer "Back" moved to the standard navigation‑bar position.
- **Up Next** section on genuinely quiet days (empty, all recovery, or all done).

Test infrastructure
- UI test classes isolated to `@MainActor`, clearing **181** latent
  strict-concurrency warnings in the test target. They had never re-printed
  because incremental builds were not recompiling that target — a reminder that
  a warning count from an incremental build proves nothing.
- `completeOnboarding` now waits for *hittability*, not mere existence, before
  tapping Continue. The button exists on every onboarding step, so under
  simulator load a tap could fire before the previous step settled. This was a
  test defect; no product code changed in response.

Migration
- **None required.** The SwiftData schema is unchanged, and workout ids are
  derived from the plan's canonical day index, so changing preferred days moves
  dates while preserving completion history.


### 2026‑07‑25 — Stage 2b: first Xcode build; the app compiles, tests, and runs

The app layer had been authored without a compiler ever seeing it. It now
builds, tests, and launches.

Fixed (3 files, the complete set of first‑build failures)
- **`NotificationScheduler`** — Swift 6 strict concurrency. The class is now
  `@MainActor` (it is owned by the main‑actor `AppEnvironment` and holds a
  non‑`Sendable` `deepLinkHandler`), while the two
  `UNUserNotificationCenterDelegate` witnesses are `nonisolated` and hop to the
  main actor themselves. `UNUserNotificationCenterDelegate` is not `@MainActor`
  and its parameters are not `Sendable`, so isolating the class alone was
  insufficient.
- **`NotificationSettingsView`** — `Section(_ title:) { } footer: { }` is not a
  valid initializer; a string title and a footer are mutually exclusive. Switched
  to the explicit `header:` / `footer:` form.
- **`Info.plist`** — added `CFBundleIdentifier`, `CFBundleExecutable`,
  `CFBundlePackageType`, `CFBundleInfoDictionaryVersion` and
  `CFBundleDevelopmentRegion`. Without them the Simulator refused to install the
  app ("Missing bundle ID"); XcodeGen injects these only under
  `GENERATE_INFOPLIST_FILE`, which this target does not use.

Verified (Xcode 26.6, iOS 26.5 SDK, iPhone 17 Simulator)
- `xcodebuild build` — **0 errors, 0 warnings**.
- `xcodebuild test` — **6 tests passing** (4 app unit, 2 UI).
- The app **installs, launches, and renders onboarding**; SwiftData creates its
  persistent store (no in‑memory fallback). First screenshot captured to
  `docs/screenshots/`.
- `swift test` — **57 domain tests passing**; plan JSON still byte‑reproducible
  at 36 weeks / 252 days / 382 workouts.

Documentation
- `README.md`, `LIMITATIONS_AND_NEXT_STEPS.md` corrected — they described a
  headless, Xcode‑less environment and listed the six screens as unimplemented,
  both of which are no longer true.

### 2026‑07‑25 — Stage 1–2: research, decisions, and verified domain core

Added
- **Research** (primary‑source, cited): Apple platform state (iOS 26 SDK, min iOS
  18), UserNotifications 64‑request cap + rolling‑window strategy, HealthKit /
  WorkoutKit authorization model, Swift Charts accessibility, App Store Review &
  TestFlight, and long‑course triathlon periodization / fueling / open‑water
  safety. See `DECISIONS.md`, `TRAINING_SOURCES.md`.
- **`EnduranceDomain` SwiftPM package** (Foundation‑only, no SwiftUI) — the shared
  core consumed by the app, watch, widgets, intents, and tests:
  - Value types: `Sport`, `IntensityZone`, `StressCategory`, `WorkoutStatus`,
    `MeasurementSystem`, `AccentToken`.
  - Immutable plan schema: `TrainingPlanDefinition` → phases → weeks → days →
    `WorkoutTemplate` → recursive `WorkoutStep`; nutrition/recovery guidance.
  - Mutable state: `ScheduledWorkout`, `WorkoutCompletion`, `PlanModification`,
    `WorkoutIdentity` + `ExternalWorkoutReference`, `ScheduleConfiguration`,
    `NotificationPreferences`, `SharedTodaySnapshot`.
  - Services: `ScheduleEngine` (DST/leap/tz‑safe), `PlanValidator`, `PlanCodec`,
    `UnitFormatter`, `ProgressCalculator`, `NotificationPlanner`,
    `AdaptationAdvisor`, `ExportService`, `UUIDv5`.
- **51 Swift Testing tests, all passing** (`swift test`), covering date
  generation, DST spring‑forward/fall‑back, leap year, race↔start conversion,
  week/phase lookup, unit conversion + round trips, plan validation (valid +
  malformed), completion %, planned‑vs‑completed, per‑sport aggregation,
  consistency, reschedule conflict rules, notification identifiers / cancellation
  / regeneration / rolling window / 64‑budget, and export/import round trips
  (incl. an RFC‑4122 UUIDv5 vector).
- **`PlanGenerator` + `enduranceplan` tool** — deterministically generates the
  full **36‑week · 252‑day · 382‑workout** plan, validates it, and encodes a
  byte‑reproducible `Endurance36Week.json` bundled by `EnduranceTrainingPlans`.
  6 more tests lock in structure, the long‑run cap, brick coverage, and
  generator↔JSON sync (**57 tests total, all green**).
- **Project generation:** `project.yml` (XcodeGen; app + unit + UI test targets),
  `Applications/iOS/Info.plist`, `Endurance.entitlements` (App Group), and
  `Assets.xcassets` (AppIcon slot, AccentColor, LaunchBackground).
- **SwiftUI app layer (authored for Xcode — 27 files):** composition root
  (`EnduranceApp`, `AppEnvironment`, `AppConfig`, `AppLog`, `DeepLink`,
  `RootView`); design system (`Theme`, `Components`, `DisplayFormatter`,
  `PreviewSupport` with Dark/large-type previews); SwiftData persistence
  (`Models`, `WorkoutStore`) keeping the domain value types as source of truth;
  services (`NotificationScheduler` bridging `NotificationPlanner` →
  `UNUserNotificationCenter`, `SnapshotWriter`); and all six screens —
  Onboarding, Today (+ row, week progress, completion & reschedule sheets),
  Workout Detail (+ structured step rows), Plan (+ week detail), Progress (Swift
  Charts), Settings (+ notifications, plan dates, zones). App unit tests
  (`DeepLink`, `DisplayFormatter`) + a UI smoke test.
- **Documentation:** `DECISIONS.md`, `DATA_SCHEMA.md`, `TRAINING_SOURCES.md`,
  `EXPANSION_ARCHITECTURE.md`, `CAPABILITIES.md`, `README.md`, `PRIVACY.md`,
  `QA_CHECKLIST.md`, `ICON_SPEC.md`, `UX_SPEC.md`,
  `LIMITATIONS_AND_NEXT_STEPS.md`, and this changelog.

Verified
- `swift build`, `swift test` (57 tests), and `swift run enduranceplan` succeed
  with **zero warnings** on Swift 6.1. Plan JSON is byte‑identical across runs.

### Next (planned, this release)
- Add accessibility identifiers on onboarding/Today controls — a §20 requirement,
  and the blocker on UI tests that can assert more than "the app launched".
- Drive onboarding end to end in a UI test, then assert that completion and
  rescheduling survive relaunch (§31).
- Move user‑facing strings into a String Catalog (§28.18) before the codebase
  grows further.
- Run the `QA_CHECKLIST.md` matrix (Dark Mode, largest Dynamic Type, VoiceOver,
  Reduce Motion) and capture screenshots of every screen.
- Verify on a physical iPhone, including notification delivery and deep‑link taps.
- Draw the app‑icon art per `ICON_SPEC.md`; add haptics, per‑workout interval
  check‑off, and Plan filtering (all already supported by the data model).
