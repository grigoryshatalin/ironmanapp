# UX_SPEC.md — Endurance

Screen-by-screen UX specification (the brief's §32 item 4). Grounded in §6–§12
and §20–§21, and matched to the SwiftUI implementation under `Applications/iOS`.

## Principles

- **Native first.** Standard `List`/`Form`/`NavigationStack`/`TabView`, sheets,
  `swipeActions`, `contextMenu`, `confirmationDialog`, `ShareLink`,
  `ContentUnavailableView`. No custom re-implementations of system controls.
- **Calm, not gamified.** No confetti, streaks, XP, neon, or punishment language.
  A missed workout is never a red error. Progress is informational.
- **Today is the center.** The Today screen answers "what do I do today?" within
  ~1 second: date, week/phase, one status line, the sessions.
- **Safety over statistics.** Reschedules surface advisory conflict warnings and
  never auto-stack hard days. Recovery weeks are labelled so lighter volume reads
  as intended.
- **Progressive disclosure.** Rows show essentials; detail expands warm-up/main/
  cool-down, cues, fueling, gear, safety.
- **Offline, private.** No network, accounts, analytics in Release 1.
- **Status is never color-only.** Every status/sport pairs a symbol + text label.

## Visual system

- **Type:** system text styles only (`.largeTitle`…`.caption`), Dynamic Type incl.
  accessibility sizes. Hierarchy via spacing/grouping, not heavy bold.
- **Color:** semantic system colors (auto Light/Dark/Increased-Contrast). Restrained
  sport accents — swim cyan, bike orange, run green, strength indigo, recovery
  purple, race primary accent — always secondary to content; never full-screen
  washes (`Theme.swift`).
- **Symbols:** SF Symbols with verified availability + fallback
  (`Theme.availableSymbol`).
- **Spacing:** 4/8/12/16/20/24/32 (`Theme.Space`). Native grouped backgrounds and
  separators do the structural work; cards only for the next workout / summaries.
- **Materials/motion:** system bars/sheets; sparing material; subtle native
  animation + haptics on complete/reschedule; honor Reduce Motion.

## Navigation architecture

`RootView` → `TabView` with four tabs, **each its own `NavigationStack`**:

1. **Today** (`figure.mixed.cardio`) → Workout Detail; Completion sheet; Reschedule sheet.
2. **Plan** (`calendar`) → Week Detail → Workout Detail.
3. **Progress** (`chart.xyaxis.line`) → (metric detail — future).
4. **Settings** (`gearshape`) → Notifications, Plan dates, Training zones, Data, About.

Onboarding is shown instead of the tabs until the plan is configured. Notification
taps deep-link via `endurance://workout/<id>` / `review/<week>` and route the tab
+ pushed screen (`AppEnvironment.route`).

## Onboarding (6 steps) — `OnboardingView`

A short, native paged flow with a top `ProgressView` and Back/Continue footer. No
marketing carousel.

1. **Purpose** — what the app does + the non-medical disclaimer.
2. **Schedule** — segmented "Start date / Race date"; a `DatePicker` for the chosen
   one; the derived date is shown **immediately** below.
3. **Weekly structure** — weekday/weekend default times (`DatePicker` hour+minute),
   long-ride / long-run / rest weekday pickers, units.
4. **Current capability** — optional toggles (pool / open-water / trainer /
   strength); framed as informing future guidance, never silently rewriting.
5. **Notifications** — per-category toggles, all OFF by default; permission is
   requested only on finish **if** ≥1 category is enabled.
6. **Safety** — calm acknowledgment; "Start training" is disabled until confirmed.

On finish: build `ScheduleConfiguration` + `NotificationPreferences`, call
`store.completeOnboarding` (validates the bundled plan, generates the schedule,
persists), request notification auth if needed, refresh side-effects.

## Today — `TodayView`

```
Saturday, August 15                         ← .title2
Week 4 of 36 · Base                         ← .subheadline secondary
▓▓▓▓▓░░░░  45m of 150m · 1/2 sessions       ← WeekProgressBar (purple on recovery)
────────────────────────────────────────
◔  Ready for today — 2 sessions             ← one calm status line
────────────────────────────────────────
TODAY'S SESSIONS
🚲  Endurance ride            6:30 AM  ›     ← SportBadge + title + time
    Steady, well-fuelled time in the saddle
    ⏱ 2h 30m   📏 70 km   🎚 Z2 · Endurance  ← MetricPills
🏊  Recovery swim (Optional)  5:00 PM  ›
```

- **Header:** long date, "Week N of 36 · Phase", compact `WeekProgressBar`
  (completed vs planned minutes, sessions; recovery weeks tinted purple + labelled).
- **Status line:** one of — Recovery day / All sessions complete / One session
  remains / Ready for today · N sessions / Race week. Never shame-based.
- **Rows** (`TodayWorkoutRow`): sport symbol, title, start time, one-line
  objective, metric pills (duration, distance when applicable, intensity/zone),
  status chip when not planned.
- **Interactions:** tap → detail; trailing swipe → Complete; leading swipe →
  Reschedule; context menu → Complete / Reschedule / Replace with recovery / Skip,
  and Undo for non-planned. Completing opens the Completion sheet and **cancels the
  workout's pending reminders**.
- **Empty state:** `ContentUnavailableView` "Nothing scheduled today."

**Completion sheet** (`CompletionSheet`): actual duration stepper, optional
distance, RPE/fatigue/soreness sliders, notes. Save with nothing filled records
"done". **Reschedule sheet** (`RescheduleSheet`): `DatePicker` + advisory
`AdaptationAdvisor` warnings (each with "what stays unchanged"); never blocks.

## Workout Detail — `WorkoutDetailView`

Grouped sections: header (sport, date/time, metric pills, status), Purpose (+
stress category & RPE hint), **Warm-up / Main set / Cool-down** rendered as
structured `StepRow`s (repeats shown as "N ×", nested children indented — not a
text wall), Technique, Fueling & hydration (ranges + "targets not prescriptions;
don't overdrink"), Gear & safety (safety notes tinted), Your session (logged
actuals), Modification history. Primary toolbar action: **Complete**.

## Plan — `PlanView` / `WeekDetailView`

- **Plan:** weeks grouped by **phase** (section header = phase name + objective).
  `WeekRow`: "Week N", load tag (recovery tinted purple), planned hours, date
  range, key long workout (star), and for past weeks a "x/y done" summary.
- **Week Detail:** objective, planned time, recovery-week note, coach note; then a
  section per day (weekday + date header) listing that day's sessions → detail.
- **Filtering** by sport/status is supported by the data model (`workouts(inWeek:)`
  + status) and is the next Plan increment.

## Progress — `ProgressDashboardView`

Swift Charts, restrained, **separate charts per unit** (no mixed-unit chart):

- **Planned vs completed minutes** by week (grouped `BarMark`; completed in accent,
  planned in muted) — last 12 weeks.
- **Completion by sport** this week (symbol + "x/y").
- **Consistency** last 4 weeks (`Gauge` + %).
- A footnote states recovery weeks are meant to be lighter — lower volume there is
  the plan working. Charts carry `accessibilityLabel`/`accessibilityValue` per mark
  and an overall label (audio graph available via Swift Charts).
- Empty state until there's history.

## Settings — `SettingsView`

Native grouped `Form`/`List`:

- **Plan:** Units picker (persists + reformats); "Adjust start / race date" →
  `PlanDatesView` which **explains what changes** (future dates recalculated,
  completed sessions preserved, reminders refreshed) before applying.
- **Reminders:** → `NotificationSettingsView` — authorization status (Allowed /
  Off with **Open Settings** / Enable), per-category toggles, workout lead-time and
  scheduling-window steppers, and a note about the 64-reminder system limit.
- **Training:** Training zones (RPE table; sensors optional/future); Health access
  (future, greyed).
- **Data:** Export training data (JSON) via `ShareLink`; Reset completion history
  and Delete all data via `confirmationDialog`.
- **About:** version, on-device privacy statement, non-medical disclaimer.

## Empty / loading / error / unusual states (§21)

Handled with `ContentUnavailableView` and calm copy; never a raw error:
first launch → onboarding; no workout today / recovery day / all complete → Today
status + empty state; plan validation failure → `BundledPlans.LoadError` surfaced
as a recoverable alert; persistence failure → in-memory fallback + "Couldn't open
your data" alert (data safe, relaunch); no history yet → Progress empty state;
date in the past → allowed (schedule computed as-is); moving across weeks / skipping
a week → advisory warnings, still permitted; reset/delete → confirmation then back
to onboarding; export failure → "Export didn't finish" alert.

## Accessibility (per screen)

- Dynamic Type incl. accessibility sizes throughout; critical workout info never
  truncated (rows allow wrapping; pills stay legible).
- VoiceOver: rows combine into a single meaningful label
  (`TodayWorkoutRow.accessibilityText`); status announced by label, not color;
  charts have per-mark labels/values + an overall description; the week progress
  bar announces "x of y sessions, recovery week".
- Differentiate Without Color (symbol+text everywhere), Reduce Motion (subtle
  system animations only), Bold Text / Increased Contrast via semantic styles.
- Accessibility identifiers to be added on onboarding + Today controls for
  `XCUITest` (`OnboardingUITests` is scaffolded).
