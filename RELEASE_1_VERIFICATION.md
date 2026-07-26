# Release 1 — Verification Report

**Endurance** · 36-week full-distance triathlon training app
Verification date: **2026-07-26**
Toolchain: Xcode 26.6 (17F113) · iOS 26.5 SDK · Swift 6.3.1, Swift 6 language mode, `SWIFT_STRICT_CONCURRENCY: complete`

> **Release 1 is not declared complete.** One acceptance criterion — on-device
> notification verification — could not be executed because no physical iPhone
> is connected to this machine. Section 4 states exactly what remains and what
> was substituted. Everything else in the refinement pass is implemented and
> verified.

---

## 1. Test commands and results

### 1.1 Domain package

```sh
cd EndurancePackages && swift test
```

**69 tests in 11 suites — all passing.** Zero warnings.

| Suite | Covers |
|---|---|
| Schedule engine — dates, DST, leap years, conversion | §17 date engine |
| **Preferred day layout** *(new)* | §7 long-ride / long-run / rest day transform |
| Plan validation · Plan lookup | §15 schema, §10 week/phase lookup |
| Unit conversion & formatting | §12 units |
| Progress aggregation | §11 |
| Notification planning — identifiers, cancellation, window, budget | §13 |
| Adaptation & reschedule conflict rules | §14 |
| Export / import round trips & deterministic ids | §12, §31 |
| Bundled 36-week plan | §16 content |
| Toolchain probe | environment sanity |

### 1.2 Application unit tests

```sh
xcodebuild test -project Endurance.xcodeproj -scheme Endurance \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

**4 tests — all passing** (`DeepLink` parsing, `DisplayFormatter` duration and
unit-aware distance).

### 1.3 UI acceptance suite (`EnduranceUITests`) — **7 tests, all passing**

This suite **replaced** the previous two smoke tests. Those asserted only that
the app reached the foreground, and passed whether onboarding *or* the Today tab
was showing — they could not fail for any product reason. Every test below
matches on accessibility identifiers, never on user-facing English, so the suite
survives localization.

| Test | Requirement |
|---|---|
| `testOnboardingGeneratesFullThirtySixWeekSchedule` | 1, 2 — onboarding completes from a fresh install; **382 sessions** scheduled |
| `testTodayShowsTodaysDateAndSessions` | 3 — Today's header equals today's date; sessions listed |
| `testCompletionPersistsAcrossRelaunch` | 4, 5, 6 — complete → terminate → relaunch → status matches |
| `testReschedulePersistsAcrossRelaunch` | 7, 8, 9 — reschedule → terminate → relaunch → new date holds |
| `testChangingStartDateRegeneratesFutureWorkouts` | 10, 11 — anchor moved forward; Today clears and Up Next appears |
| `testExportIsWrittenAndParsesBack` | 12, 13 — export written, decoded back, 382 sessions |
| `testCriticalScreensSurviveLargestDynamicType` | §20 |

Requirements 12 and 13 are verified through a real product surface rather than a
test-only hook: **Settings → Export contents** is rendered by encoding the
export, writing it, and *decoding the written file back*. If the export did not
parse, the row would not appear. A corrupt export is therefore visible to the
athlete before it is ever shared.

### 1.4 Accessibility matrix (`AccessibilityMatrixTests`) — **9 tests, all passing**

Each launches with the setting forced on and asserts the athlete can still see
the date, see the day's status, and open the first session.

Light Mode · Dark Mode · Reduce Motion · Increased Contrast · Differentiate
Without Color · Bold Text · Smallest Dynamic Type · Largest Dynamic Type ·
VoiceOver labelling.

### 1.5 Screenshot capture (`ScreenshotTests`) — **9 tests, 13 images**

```sh
./Tools/capture-screenshots.sh
```

### 1.6 Device matrix

| Device | Suite | Result |
|---|---|---|
| iPhone 17 | full (unit + UI + a11y + screenshots) | pass |
| iPhone 17 Pro | full | pass |
| iPhone 17e (**small screen**) | acceptance | **7/7** |
| iPhone 17 Pro Max (**large screen**) | acceptance | **7/7** |

### 1.7 Build hygiene

`xcodebuild build-for-testing` — **0 errors, 0 warnings** across the app and all
test targets. The only console line is `appintentsmetadataprocessor: No
AppIntents.framework dependency found`, which is expected: App Intents ship in
Release 2.

**Correction worth recording.** Intermediate runs during this pass reported "0
warnings" while the UI test target actually carried **181** strict-concurrency
warnings — `XCUIElement`'s methods are `@MainActor`, and the test classes were
not. Incremental builds were not recompiling that target, so the warnings never
re-printed. They surfaced only when adding a file forced a full recompile. Fixed
by isolating the three UI test classes and the shared helper to `@MainActor`, and
by initializing the `XCUIApplication` inline rather than mutating main-actor state
from `XCTestCase`'s nonisolated `setUp()`.

The lesson generalises: **a warning count from an incremental build is not
evidence.** Build hygiene should be read from a full `build-for-testing`.

### 1.8 Test robustness

A confirmation run on a fourth simulator (iPhone 17 Pro) initially failed two
acceptance tests — `testCompletionPersistsAcrossRelaunch` and
`testTodayShowsTodaysDateAndSessions`. Investigated rather than dismissed:

- Neither failure was an assertion failure. Both were XCUITest event-synthesis
  timeouts (`Failed to tap … Timed out while synthesizing event`), and the second
  test took **236 s** against a normal 19 s.
- Cause: the run overlapped with a second booted simulator running the app
  interactively, so the host was contended.
- Both passed in isolation on the same device, at normal timings.

This was a **test defect, not a product defect**: `completeOnboarding` tapped
Continue five times waiting only for *existence*, and that button exists on every
step — so under load a tap could fire before the previous step had settled. The
helper now waits for hittability. No product code was changed in response.

---

## 2. Manual device and simulator results

**Simulator:** verified. The app installs, launches, completes onboarding,
generates and persists a 36-week schedule, and survives terminate/relaunch. All
appearance and accessibility configurations in §1.4 were exercised
programmatically, and every screen was captured (§3).

**Physical device: NOT verified.** `xcrun devicectl list devices` reports no
connected devices. Nothing in this report should be read as covering real
hardware.

---

## 3. Screenshots

`docs/screenshots/` — regenerated reproducibly by `Tools/capture-screenshots.sh`.

| File | Screen |
|---|---|
| `01-onboarding.png` | Onboarding — purpose + safety framing |
| `02-onboarding-schedule.png` | Onboarding — start/race anchor with derived date |
| `03-today-multiple-workouts.png` | Today, two sessions (week 5) |
| `04-today-recovery-day.png` | Recovery day + **Up next** |
| `05-workout-detail.png` | Workout detail |
| `06-plan-weeks.png` | Plan, weeks grouped by phase |
| `07-plan-week-detail.png` | Week detail |
| `08-progress.png` | Progress (Swift Charts) |
| `09-settings.png` | Settings |
| `10-today-dark.png`, `11-plan-dark.png` | Dark Mode |
| `12-today-largest-dynamic-type.png` | Largest Dynamic Type |
| `13-workout-detail-largest-dynamic-type.png` | Detail at largest Dynamic Type |

---

## 4. Remaining known issues

### 4.1 Blocking Release 1 sign-off

**On-device notification verification (priority-1 item 4) — not done.** No
physical iPhone is connected, and the Simulator cannot honestly stand in for
delivery, tap-through, or background rescheduling.

What *is* verified, in the domain suite, is the entire decision layer:

| Sub-requirement | Status |
|---|---|
| Stable notification identifiers | ✅ unit-tested (deterministic, derived, not random) |
| No duplicate notifications | ✅ unit-tested (id-keyed reconciliation) |
| Cancellation after completion | ✅ unit-tested |
| Regeneration after rescheduling | ✅ unit-tested |
| Regeneration after a date change | ✅ unit-tested |
| Rolling scheduling window · ≤64 budget | ✅ unit-tested, including the cap |
| Permission flow | ⛔ needs a device |
| Actual reminder delivery | ⛔ needs a device |
| Tap → deep link to the right workout | ⚠️ `DeepLink` parsing unit-tested; the tap path itself needs a device |

To close this: connect an iPhone, set a development team and unique bundle id in
*Signing & Capabilities*, run, enable a reminder category with a near-future
time, background the app, and confirm delivery, non-duplication, and that a tap
opens the correct session.

### 4.2 Non-blocking

- **Interval check-off is session-scoped.** Ticks are held in view state and
  reset when you leave the screen. Persisting them means a schema change, which
  §28.22 requires a migration for; deferred deliberately rather than shipped
  half-done. It is explicitly optional and nothing depends on it.
- **`-uiTestStartDayOffset` is DEBUG-only test surface.** It backdates
  onboarding's start date so captures and tests land on a chosen plan day.
  Compiled out of Release builds.
- **Weekly progress is hidden at accessibility text sizes** on Today. This was a
  deliberate fix, not an omission — see §5.
- **Training zones remain RPE-only.** Heart-rate/power/pace zone editing is
  still a later update; the app is fully usable without sensors.
- **HealthKit, watchOS, widgets, Siri are absent.** Release 2 by design.
- **Localization is English-only.** The infrastructure is in place (§6); adding
  a language is now a translation task.

---

## 5. Defects found and fixed during this pass

Recording these because each was a real product defect, not a cosmetic tweak.

1. **Onboarding collected preferences and ignored them.** The preferred
   long-ride, long-run, and rest days were written to `ScheduleConfiguration`
   and never applied. Now implemented as `WeekdayLayout`, which permutes *whole
   days* within each week — so a brick run stays attached to its ride and
   recovery stays after the long run. Covered by 12 new tests, including one
   asserting the brick stays with its ride and one asserting workout identity
   survives a preference change.
2. **`PlanDatesView` silently discarded preferences.** Changing the start date
   rebuilt the configuration from scratch, dropping the athlete's preferred
   days. It now carries the existing configuration forward.
3. **Today was unusable at the largest Dynamic Type.** The header consumed the
   entire screen and pushed all sessions off it — defeating the one question the
   screen exists to answer. Caught by the new accessibility matrix test, then
   fixed by shortening the date and yielding the secondary progress bar at
   accessibility sizes.
4. **Completion sheet ignored the athlete's units.** Distance was entered and
   stored as metric regardless of the chosen measurement system.
5. **Container-level accessibility identifiers erased every descendant's.** In
   SwiftUI, `.accessibilityIdentifier` on a `List`/`NavigationStack` overrides
   the whole subtree; the first diagnostic dump showed exactly one button in the
   entire tree. All container identifiers were removed and identifiers now sit
   on leaves.
6. **False precision in distances.** Planned rides read `30.35 km`, implying a
   measurement the plan does not have. Now one decimal.

---

## 6. Data migration impact

**None. No migration is required for this release.**

- The SwiftData schema is unchanged: `SDScheduledWorkout` and `SDAppSettings`
  have the same properties as the previous build. No property was added,
  removed, renamed, or retyped.
- `ScheduleConfiguration` already carried `preferredLongBikeWeekday`,
  `preferredLongRunWeekday`, and `preferredRestWeekday`. This pass began
  *honouring* fields that were already persisted, so existing stores decode
  unchanged.
- **Workout identity is deliberately stable across the new transform.**
  `deterministicScheduledID` is derived from the plan's *canonical* day index,
  not the permuted one. Changing preferred days moves dates but preserves ids —
  so completion history matches straight across. `WeekdayLayoutTests`
  asserts this explicitly.
- Applying preferred days never moves a session that is already completed or in
  the past (`WorkoutStore.applyPreferredDays`).
- The export format (`TrainingHistoryExport`, `schemaVersion 1`) is unchanged;
  exports from the previous build still decode.

---

## 7. Forward-compatibility with the planned releases

The changes in this pass were made in the shared domain or the app layer only,
and none of them narrows the architecture described in
`EXPANSION_ARCHITECTURE.md`.

| Planned feature | Compatible | Why |
|---|---|---|
| **HealthKit** import/export | ✅ | `WorkoutIdentity.externalReferences` unchanged; `CompletionSource.healthKit` already modelled. Matching keys off sport/start/duration/distance, all still present. |
| **watchOS** companion | ✅ | `EnduranceDomain` remains Foundation-only — `WeekdayLayout` added no UI dependency. `SharedTodaySnapshot` unchanged. |
| **WorkoutKit** | ✅ | Structured `WorkoutStep` tree untouched; interval check-off is view state and does not compete with it. |
| **Live Activities** | ✅ | No change to session state modelling. |
| **Widgets / App Intents** | ✅ | `SharedTodaySnapshot` + App Group unchanged. `A11y` identifiers are compiled into the app and UI test targets only. |
| **iCloud / CloudKit** | ✅ | Stable UUIDs preserved — strengthened, since ids now survive a preferred-day change. No new non-optional properties (CloudKit requires optional/defaulted attributes). |
| **WeatherKit** | ✅ | No location or network surface introduced; the app still makes zero network calls. |
| **Equipment mileage** | ✅ | Depends on completion records, unchanged. |
| **Coach-authored plans** | ✅ | **Improved.** `WeekdayLayout` derives long-ride/long-run/rest days *from plan content* rather than hard-coding Saturday/Sunday, so an imported plan with a different rhythm gets the correct transform. |
| **Garmin / Strava** | ✅ | `ExternalWorkoutReference` untouched; no provider code leaked into the domain. |
| **Localization** | ✅ | **Advanced.** String Catalog added, domain enums resolve through it, and tests match identifiers not text. |

Two forward-looking notes, stated plainly:

- Persisting interval check-off **will** require a schema version bump and
  migration fixtures per §28.22. It has not been done.
- Enabling CloudKit will still require the standard audit that every SwiftData
  property is optional or defaulted. This pass did not add properties, so that
  audit is no larger than it was.

---

## 8. Acceptance status

| Priority | Item | Status |
|---|---|---|
| 1 | 1. Accessibility identifiers | ✅ 79 identifiers across all listed surfaces |
| 1 | 2. Deterministic UI tests replacing smoke tests | ✅ 7 tests, all 13 sub-requirements |
| 1 | 3. Preferred days wired into the transform | ✅ + 12 domain tests |
| 1 | 4. Notifications on a physical device | ⛔ **blocked — no device connected** |
| 2 | 5. String Catalog introduced | ✅ before any Release 2 interface exists |
| 2 | 6. User-visible strings localized | ✅ 63 catalog keys + literal extraction enabled |
| 2 | 7. VoiceOver labels, values, hints, traits | ✅ + asserted in tests |
| 2 | 8. Accessibility/appearance matrix | ✅ 9 automated + small/large device runs |
| 3 | 9. Fewer floating cards | ✅ Today header/status merged into one grouped section |
| 3 | 10. Native grouped sections and controls | ✅ |
| 3 | 11. Standard navigation back | ✅ — see note below |
| 3 | 12. No truncated metadata | ✅ `MetricLine`, wraps instead of truncating |
| 3 | 13. Up Next on quiet days | ✅ shown only when the day is genuinely quiet |
| 3 | 14. Standardized sport symbols | ✅ one frame, mode, weight, alignment, label, fallback |
| 3 | 15. Secondary-text contrast, semantic colors only | ✅ hard-coded `.green`/`.purple` status tints removed |
| 3 | 16. Haptics on completion/reschedule/export | ✅ via `sensoryFeedback` |
| 4 | 17. Plan filtering | ✅ sport + completed/missed/modified |
| 4 | 18. Optional interval check-off | ✅ optional, nothing depends on it |
| 4 | 19. App icon artwork | ✅ generated from `Tools/GenerateAppIcon.swift` |
| 4 | 20. Screenshots | ✅ 13 images |

**On item 11:** there was no large custom circular back button in the codebase —
every screen already used `NavigationStack` with the system back affordance. The
closest match was onboarding's bordered "Back" button in the footer, which has
been moved to the standard `navigationBarLeading` position with a chevron.
Reporting this rather than inventing a change to a control that did not exist.

---

## 9. Definition of done — §31

| Criterion | Status |
|---|---|
| Builds without errors | ✅ |
| No unexplained warnings | ✅ 0 |
| Launches on a supported simulator | ✅ 4 device models |
| Physical-device workflow valid | ⛔ untested |
| Onboarding produces a usable schedule | ✅ asserted |
| Today shows the correct date and sessions | ✅ asserted |
| Full 36-week plan imports | ✅ 382 sessions asserted |
| Completion persists after relaunch | ✅ asserted |
| Rescheduling persists after relaunch | ✅ asserted |
| Notifications not duplicated | ⚠️ unit-tested only |
| Completed workouts have reminders cancelled | ⚠️ unit-tested only |
| Date changes regenerate future scheduling | ✅ asserted |
| Progress calculations tested | ✅ |
| Light and Dark Mode intentional | ✅ tested + captured |
| Large Dynamic Type usable | ✅ tested + a real defect fixed |
| VoiceOver labels meaningful | ✅ asserted |
| Works offline | ✅ no network code exists |
| Exported data re-importable | ✅ round-trip in-app and asserted |
| No health data leaves the device | ✅ |
| Documentation sufficient to continue | ✅ |

**Recommendation:** hold Release 1 sign-off until §4.1 is closed on hardware.
Everything else is done and verified.
