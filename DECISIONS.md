# DECISIONS.md — Endurance

Architecture and UX decisions of record. Where current Apple documentation
conflicts with assumptions in the original brief, **current documentation
wins** and the change is noted here (per the brief, §2). Research was conducted
mid‑2026 against primary sources; citations are inline.

> Working product name: **Endurance**. It is isolated in `project.yml`
> (`PRODUCT_NAME`, display name) and `EnduranceDomain.productName`, so a rename
> touches two places, not the whole codebase.

---

## 0. TL;DR technical recommendation

Build a **native SwiftUI app** on a **Foundation‑only shared domain package**,
persisted with **SwiftData**, reminded by **local UserNotifications** on a
rolling ≤64 window, charted with **Swift Charts**, with **HealthKit / WorkoutKit
/ Watch / Widgets / iCloud** as clearly separated optional layers wired but not
all implemented in Release 1. No third‑party runtime dependencies. Build against
the **iOS 26 SDK (Xcode 26)**; **minimum deployment iOS 18.0 / watchOS 11.0**.

---

## 1. Why SwiftUI (not UIKit, not anything cross‑platform)

- The brief forbids React Native / Expo / Flutter / Ionic / Electron / web views
  for the primary UI, and requires a first‑party feel. SwiftUI is Apple's
  current primary UI framework and is the only realistic way to share UI idioms
  across iPhone, **Apple Watch**, **widgets**, and **Live Activities** (all on
  the Release 2–4 roadmap) from one codebase.
- SwiftUI gives Dynamic Type, Dark Mode, semantic colors, VoiceOver, and Reduce
  Motion largely for free when standard controls are used — directly serving the
  "accessibility is a release requirement" mandate.
- UIKit is used only if/when a specific control is missing; none is required for
  the MVP.

## 2. Supported iOS version

- **Build SDK:** iOS 26 (Xcode 26, Swift 6.3) — the newest *stable* SDK in
  mid‑2026. iOS 27 / Xcode 27 exist only as betas and are not used (brief: "Do
  not require beta SDKs"). Sources: endoflife.date/ios; Apple Xcode 26.6 release
  notes.
- **Minimum deployment: iOS 18.0 / watchOS 11.0.**
  - Research recommended iOS 17 as the floor (SwiftData + WorkoutKit + Swift
    Charts all land at 17). We deliberately raise it to **18** because: (a) this
    is a personal / TestFlight app where device reach is irrelevant; (b)
    SwiftData is materially more robust by iOS 18; (c) **WorkoutKit custom
    _swimming_ workouts require iOS 18 / watchOS 11** (WWDC24), which a triathlon
    app needs in Release 2, so 18 avoids a wall of `@available` gates.
  - Features that need even newer OSes (e.g. SwiftData model inheritance = iOS
    26) are gated with `@available`, never by raising the whole app's floor.
- The shared `EnduranceDomain` SwiftPM package declares a lower floor
  (`.iOS(.v18)`, `.watchOS(.v10)`, `.macOS(.v14)`); the macOS platform exists
  **only** so the domain layer's tests run on a plain Swift toolchain — it is
  not a shipping target.

## 3. Persistence

- **SwiftData** is the store of record for mutable user state (scheduled
  workouts, completions, modifications, settings, notification bookkeeping). It
  is Apple's current recommendation for greenfield SwiftUI apps and is the path
  to **CloudKit private sync** in Release 3. Source: Apple, "Adopting SwiftData
  for a Core Data app."
- **Immutable plan content is NOT in SwiftData.** It ships as **versioned,
  validated JSON** in the `EnduranceTrainingPlans` bundle and is decoded into the
  Foundation value types in `EnduranceDomain`. Rationale: the plan is read‑only
  reference data; keeping it out of the mutable store means a plan update can
  never corrupt or duplicate history, and the same JSON drives tests, previews,
  export, and coach‑authored plans (Release 4).
- **Separation of concerns (brief §18):** bundled plan → `PlanRepository`;
  date mapping → `ScheduleEngine`; user state → `WorkoutRepository`; reminders →
  `NotificationScheduler`; progress → `ProgressCalculator`; health →
  `HealthService`; export → `ExportService`; validation → `PlanValidator`. The
  pure‑logic half of each already exists and is unit‑tested in `EnduranceDomain`;
  the app layer adds the SwiftData/UNUserNotificationCenter/HealthKit adapters.
- Core Data is kept in reserve only if a future feature needs **shared**‑database
  CloudKit sync (multi‑user), which SwiftData still lacks — not anticipated.

## 4. Notification strategy

Grounded in the **hard 64 pending‑request limit** (the system silently keeps only
the 64 soonest and drops the rest — Apple Developer Forums, quoting an Apple
Frameworks engineer, thread 811171):

- **Rolling window, not fire‑and‑forget.** `NotificationPlanner` (pure, tested)
  computes the desired set within a configurable window (default 21 days),
  deduplicated by stable id, sorted soonest‑first, and **capped at ≤64**. The app
  refreshes this on launch, foreground, and any plan/settings change (brief §13).
- **Stable, derivable identifiers** tied to the workout id
  (`workout.<uuid>`, `preparation.<uuid>`, `fueling.<uuid>`, `second.<uuid>`,
  `recovery.day.<n>`, `weeklyReview.<n>`), never random UUIDs — so completing or
  moving a workout cancels exactly the right requests
  (`removePendingNotificationRequests(withIdentifiers:)`).
- **Opt‑in per category**, permission requested only after ≥1 category is
  enabled. This is also required by **App Review 4.5.4** (notifications may not be
  required for the app to function). The app is fully usable with notifications
  denied.
- Interruption level defaults to `.active`. We **do not** request the
  Time‑Sensitive entitlement for the MVP (avoids an entitlement dependency) and
  **never** request Critical Alerts. Deep links route notification taps to the
  workout or weekly‑review screen.
- All generation/cancellation/regeneration logic is unit‑tested
  (`NotificationPlannerTests`, 10 tests).

## 5. HealthKit strategy (Release 2 — architected now)

- Optional, **progressive** authorization: request types only as features need
  them, with clear purpose strings (`NSHealthShareUsageDescription`,
  `NSHealthUpdateUsageDescription`). Source: Apple, "Authorizing access to health
  data."
- **Read authorization status is opaque by design** — `authorizationStatus(for:)`
  reports *share* status only, and a denied read returns empty results, not an
  error. So the app **never infers denial from empty data** and always degrades
  gracefully. (This corrects any brief assumption that read permission can be
  queried.)
- Triathlon modeling: `.swimming` / `.cycling` / `.running`, with
  `HKWorkoutActivityType.swimBikeRun` for multisport; pool vs open water is
  `HKWorkoutSwimmingLocationType`, not an activity type. Routes via
  `HKWorkoutRouteBuilder` (its own auth type).
- Import matches to planned sessions on sport + start time + duration + distance;
  ambiguous matches are shown for confirmation, never auto‑completed. External
  identifiers are stored on `WorkoutIdentity.externalReferences` to prevent
  re‑import / double counting. HealthKit is behind a `HealthService` protocol so
  the core builds and tests without it.

## 6. WorkoutKit strategy (Release 2 — architected now)

- `WorkoutKitConverting` maps a `ScheduledWorkout`'s structured steps to a
  `CustomWorkout` (warmup + repeatable `IntervalBlock`s + cooldown) or
  `SwimBikeRunWorkout`. Where a structure isn't representable, the full workout is
  **preserved in Endurance** and any simplification is disclosed — never silently
  dropped.
- **Pace is expressed via speed alerts** (WorkoutKit has no dedicated pace alert).
- `WorkoutScheduler` authorization is **separate from HealthKit's** and handled as
  its own flow.

## 7. Calendar‑date calculation

- `ScheduleEngine` is deterministic and does **all** math with `Calendar` +
  `DateComponents`, never raw seconds (brief §17).
  - Day 0 = start date; the final plan day = race day. Either the start date or
    the race date is the single source of truth (`PlanAnchor`); the other is
    derived by adding/subtracting `totalDays − 1` **calendar days**.
  - Local workout time is applied by *setting* hour/minute on the local day, so a
    6:30 session stays 6:30 across DST. **Verified** by spring‑forward
    (2026‑03‑08), fall‑back (2026‑11‑01), and leap‑day (2028‑02‑29) tests.
  - Weekday labels shown in the UI derive from the *actual* computed dates, so
    there is never a mismatch between the label and reality.
- Completed workouts keep their historical date; only future planned entries are
  recomputed when the plan moves.

## 8. Training‑plan schema

- A versioned, validated, human‑readable JSON schema (see `DATA_SCHEMA.md`).
  `schemaVersion` gates forward compatibility; `PlanValidator` rejects malformed
  plans with **actionable, located** errors (e.g. `week 5 / day 3 — dayIndex 999
  should be 31`) instead of crashing. Immutable plan content and mutable user
  state are strictly separated (`WorkoutTemplate` vs `ScheduledWorkout`).

## 9. Accessibility strategy

- Standard SwiftUI controls + semantic text styles and colors → Dynamic Type
  (incl. accessibility sizes), Dark Mode, Increased Contrast, Bold Text for free.
- Status is **never** color‑only: every status/sport pairs a symbol + text label
  (`Differentiate Without Color`). Charts get `AXChartDescriptor` / per‑mark
  labels and audio‑graph support (Swift Charts provides much of this
  automatically). Reduce Motion honored. Accessibility identifiers added for UI
  testing.

## 10. Privacy approach

- On‑device by default; **no** analytics, ads, tracking, or accounts in Release 1
  (brief §22). HealthKit/Motion data is never used for advertising or profiling
  (App Review 5.1.3) and health data is never written to iCloud outside the
  private CloudKit sync a user explicitly enables. Purpose strings are specific.
  A concise in‑app privacy statement + full `PRIVACY.md`. Data export + full
  deletion are provided. (Note the **March 26 2026 App Store medical‑device
  disclosure** obligation for Health & Fitness apps — tracked in `CAPABILITIES.md`.)

## 11. Testing approach

- **Swift Testing** for the domain layer (runs on a bare Swift toolchain — 51
  tests currently green, covering dates/DST/leap, race↔start conversion, week/
  phase lookup, unit conversion, plan validation + malformed input, completion %,
  planned‑vs‑completed, reschedule conflicts, notification identifiers/
  cancellation/regeneration/window/budget, progress aggregation, and export/
  import round trips incl. an RFC‑4122 UUIDv5 vector).
- **XCTest / Swift Testing + XCUITest** in the app target for the SwiftUI flows
  (onboarding, complete, reschedule, notification settings, race‑date change,
  week view, export, Dynamic Type, VoiceOver identifiers).
- Migration fixtures per released schema version (brief §28.22).

## 12. Build & project generation — XcodeGen

- The Xcode project is **generated from `project.yml`** via
  [XcodeGen](https://github.com/yonwoo9/XcodeGen) rather than a hand‑maintained
  `.xcodeproj`. Rationale: a multi‑target project (app + watch + widgets + Live
  Activity + intents + tests) is far more reviewable and merge‑safe as a
  declarative YAML file, and the generated `.xcodeproj` is git‑ignored.
- **XcodeGen is a developer build tool, not an app runtime dependency** — it ships
  nothing into the binary, so it doesn't violate the "avoid third‑party
  dependencies" rule (which is about runtime deps). Install via `brew install
  xcodegen`. (Tuist is a viable alternative; XcodeGen chosen for simplicity.)

## 13. Concurrency

- Swift 6 language mode with complete concurrency checking. Domain value types are
  `Sendable`; services are stateless structs. `async`/`await` at the persistence,
  HealthKit, and notification boundaries. (Swift 6 strict concurrency is opt‑in,
  not automatic — we opt in.)

## 14. Third‑party dependencies

- **Runtime: none.** Everything uses Apple frameworks.
- Build‑time: XcodeGen (project generation) — justified above.

---

## Screen‑by‑screen UX and implementation sequence

See `UX_SPEC.md` for the full screen‑by‑screen specification and
`EXPANSION_ARCHITECTURE.md` for how the MVP foundations carry every later
release. The staged implementation sequence is tracked in `CHANGELOG.md`.

## Known conflicts with the brief, resolved toward current docs

1. **Schedule‑everything notifications** → replaced by a rolling ≤64 window (64‑
   request cap is a hard system limit).
2. **Notifications as core** → made fully optional/opt‑in (App Review 4.5.4).
3. **Querying HealthKit read permission / inferring denial from empty results** →
   impossible by design; flows degrade gracefully instead.
4. **One HealthKit permission grant covering WorkoutKit scheduling** → they are
   separate authorization flows.
5. **A WorkoutKit "pace alert"** → expressed via speed alerts.
6. **Long training run up to a full marathon** → capped at a configurable
   ~18–20 mi default for a finish‑safely first‑timer (see `TRAINING_SOURCES.md`).
7. **Single fueling/hydration numbers** → configurable ranges, with an explicit
   over‑hydration (hyponatremia) warning, framed as practice targets not medical
   advice.
