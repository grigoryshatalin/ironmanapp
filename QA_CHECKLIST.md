# QA_CHECKLIST.md — Endurance

Manual, on-device QA. The **domain layer already has 57 automated tests**
(`cd EndurancePackages && swift test`) covering date generation, DST
spring-forward/fall-back, leap years, race↔start conversion, plan validation,
unit conversion, progress aggregation, notification identifiers/cancellation/
window/budget, and export/import round trips. **This checklist therefore focuses
on device, UI, accessibility, and lifecycle concerns that automated tests can't
cover.**

Run the full sheet on at least one physical iPhone before any TestFlight build.
Mark each item pass/fail; file a note for every fail.

---

## 1. Environments & display configurations

- [ ] Runs on a **physical iPhone** (not just Simulator).
- [ ] **Light Mode** looks intentional; no washed-out or invisible elements.
- [ ] **Dark Mode** looks intentional; semantic colors adapt; no pure-black-on-black.
- [ ] **Largest Dynamic Type** (accessibility sizes, `AX5`): no critical workout
      info (title, time, duration, distance, status) truncated or clipped.
- [ ] **Small-screen iPhone** (SE / mini): layouts fit; no horizontal clipping.
- [ ] **Large-screen iPhone** (Pro Max): layout uses space well; not stretched.
- [ ] **Reduce Motion** on: transitions degrade to fades/none; no parallax or
      decorative continuous animation.
- [ ] **Increased Contrast** on: separators and text remain legible.
- [ ] **Bold Text** on: layout holds; nothing overflows.
- [ ] **Differentiate Without Color** on: status/sport still distinguishable via
      symbol + label (never color alone).
- [ ] **VoiceOver**: every interactive element is reachable in a logical order
      with a meaningful label.
- [ ] **Landscape** (where supported): content reflows without loss.

## 2. Notifications

- [ ] Permission **allowed**: enabled-category reminders are scheduled.
- [ ] Permission **denied**: app remains fully usable; Settings shows the
      authorization status and an **"Open Settings"** affordance.
- [ ] Reminders fire at the **correct local time** (verify a workout reminder,
      an evening-before preparation reminder, and the weekly review).
- [ ] **Completing** a workout cancels its pending reminders (verify in
      Settings → Notifications or by waiting past the fire time).
- [ ] **Skipping / replacing** a workout cancels its reminders.
- [ ] **Rescheduling** a workout regenerates the reminder at the new time.
- [ ] Pending request count **never exceeds 64** (rolling window); far-future
      sessions are scheduled later, not dropped silently.
- [ ] Tapping a notification **deep-links** to the correct workout / weekly
      review screen (test from both foreground and cold start).
- [ ] **Per-category toggles** are respected (disable fueling → no fueling
      reminders; etc.).
- [ ] No two reminders fire at nearly the same instant for the same session.

## 3. Connectivity & lifecycle

- [ ] **Airplane Mode**: plan, Today, Plan, Progress, completion, and reminders
      all work fully offline (no account, no network required).
- [ ] **App relaunch**: completion status and reschedules persist exactly.
- [ ] **Device reboot**: data intact; scheduled reminders survive.
- [ ] **Time-zone change** (travel): future workout local times behave sensibly;
      completed workouts keep their historical records.
- [ ] **DST boundary — spring forward**: a 6:30 AM session stays 6:30 AM local.
- [ ] **DST boundary — fall back**: same; no off-by-one-hour drift.
- [ ] **Fresh install**: onboarding appears; no stale state.
- [ ] **Upgrade migration**: install an older build's data, upgrade, confirm all
      completion/history/settings preserved. **Never** requires delete & reinstall.

## 4. Core flows

- [ ] **Onboarding** completes and produces a usable schedule (start or race date
      → the other is derived and shown immediately).
- [ ] **Today** shows the correct date, training week/day, phase, and today's
      sessions **within ~1 second** of launch.
- [ ] Open a **Workout Detail**; intervals render as a readable structure, not a
      wall of text.
- [ ] **Mark complete**; log actual duration, distance, and RPE; values persist.
- [ ] **Skip** a workout (calm language, no shame).
- [ ] **Reschedule**; a move that stacks high-stress days shows an advisory
      warning; nothing moves automatically.
- [ ] **Reduce session** (shorten) updates planned load.
- [ ] **Replace with recovery**.
- [ ] **Undo** a recent status change.
- [ ] **Change race date** in Settings: explains what changes, preserves
      completed history, recalculates **future** planned dates only, and
      reschedules notifications.
- [ ] **View a week** in Plan; phase grouping and completion summary correct.
- [ ] **Progress** charts render; separate units per chart; accessible summaries.
- [ ] **Export history** (JSON) succeeds and is shareable.
- [ ] Exported data can be **re-imported / parsed** without loss.

## 5. Empty / error / unusual states (§21)

- [ ] **First launch before setup** — clear entry into onboarding.
- [ ] **No workout today** — calm, informative empty state.
- [ ] **Recovery day** — recovery messaging, not "you did nothing."
- [ ] **All workouts complete** — quiet confirmation, no confetti.
- [ ] **Plan validation failure** — actionable, human message; no raw error dump.
- [ ] **Import failure** — explains what's wrong; offers recovery.
- [ ] **No progress history yet** — helpful placeholder, not a broken chart.
- [ ] **Race date in the past** — flagged with a recovery action.
- [ ] **Start date in the past** — handled (today lands mid-plan) sensibly.
- [ ] **Move a workout across weeks** — week summaries update correctly.
- [ ] **Skip an entire week** — no cascading errors; safety guidance, no pressure
      to make up the volume.
- [ ] **Reset the plan** — native confirmation; completes cleanly.
- [ ] **Export failure** — surfaced gracefully.
- [ ] **Missing Health permission** (when HealthKit ships) — degrades gracefully.

## 6. Accessibility spot-checks

- [ ] VoiceOver announces status via **label** (e.g. "Completed"), never by color.
- [ ] Charts expose an **audio graph** and/or a text summary.
- [ ] Touch targets are comfortably large (≥ ~44 pt).
- [ ] At the largest Dynamic Type, no critical text is truncated on Today or
      Workout Detail.
- [ ] Accessibility identifiers present on key controls for UI tests.

## 7. Visual quality pass

- [ ] Native lists / grouped sections do the structural work — not a sea of
      floating rounded cards.
- [ ] No neon gradients, giant slogans, streak pressure, or punishment language.
- [ ] Typography uses semantic text styles; weight used sparingly.
- [ ] Haptics only on meaningful confirmations (complete / reschedule).
