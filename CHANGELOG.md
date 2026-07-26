# Changelog — Endurance

All notable changes to this project. The project is built through defined,
testable stages; each entry records what was added and verified.

The format is loosely [Keep a Changelog](https://keepachangelog.com/). Dates are
absolute.

## [Unreleased] — Release 1 (Core training MVP) in progress

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
- Compile the SwiftUI app layer in Xcode (`xcodegen generate`) — this environment
  has only Command Line Tools (no iOS SDK), so the app layer is authored and
  reviewed here but must be built in Xcode; fix any environment‑specific issues,
  run on Simulator + a physical device, and capture screenshots.
- Add accessibility identifiers on onboarding/Today controls and complete the
  `XCUITest` flows; run Dynamic Type / VoiceOver passes from `QA_CHECKLIST.md`.
- Draw the app‑icon art per `ICON_SPEC.md`; add per‑workout interval check‑off and
  Plan filtering (both already supported by the data model).
