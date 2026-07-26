# Known Limitations & Next Steps — Endurance

Deliverables §29 (16) known limitations and (17) next steps. Honest status of the
project as of 2026‑07‑25.

---

## Known limitations

### Build environment (most important)
- This repository was assembled in a **headless environment with only the Swift
  Command Line Tools installed — no Xcode**. Consequently:
  - ✅ The Foundation‑only **`EnduranceDomain`** package and the generated
    **36‑week plan** are genuinely **compiled and unit‑tested here** — `swift
    build` and `swift test` succeed with **57 passing tests** and zero warnings.
  - ⚠️ The **SwiftUI iOS app, watchOS app, and extensions** are authored to
    production intent against that verified core, but **have not been compiled or
    run in this environment** (they require the iOS SDK / Xcode). Expect to fix a
    handful of environment‑specific issues on first Xcode build.
  - **First action on a Mac with Xcode 26:**
    ```bash
    brew install xcodegen
    xcodegen generate
    open Endurance.xcodeproj   # then build & run
    ```
- No **App Store screenshots / preview captures** were produced — there is no iOS
  Simulator in this environment. That deliverable is pending a Simulator run
  (`xcrun simctl` + the SwiftUI previews already defined).

### Scope (release staging)
- **Release 1 (Core MVP)** is the focus. The following are **architected**
  (service protocols, layered `WorkoutIdentity`, App Group, `SharedTodaySnapshot`,
  separate packages) but their user‑facing functionality is **not implemented
  yet**:
  - R2: HealthKit import/export, Apple Watch app, WorkoutKit, Live Activities,
    Widgets, Siri/App Intents.
  - R3: iCloud/CloudKit sync, WeatherKit advisories, equipment mileage, race
    packing lists, course profiles, adaptive weekly recommendations.
  - R4: coach‑authored plans, Garmin/Strava interoperability, full localization.
- Disconnecting any of these never breaks the core (the core depends on none of
  them) — see `EXPANSION_ARCHITECTURE.md`.

### Product / content
- The 36‑week plan is a **single generic finish‑goal plan**; it is personalized
  only through scheduling (start/race date, default times). The onboarding
  **capability inputs** feed warnings/future adaptation but do not silently
  rewrite the plan.
- **Preferred long‑session / rest‑day remapping** is *recorded* in
  `ScheduleConfiguration` but the day‑rotation transform that applies it is not
  yet wired — the default weekly structure is used.
- Notifications use the **`.active`** interruption level (no Time‑Sensitive
  entitlement in the MVP, by choice).
- Training, fueling, and hydration content is **educational**, framed as
  configurable targets — not medical or coaching advice (see `TRAINING_SOURCES.md`).

---

## Next steps (prioritized)

1. **Stand up the Xcode project** — `xcodegen generate`, resolve any
   environment‑specific compile issues, run on Simulator and a physical iPhone.
2. **Implement SwiftData persistence + the six screens** (Onboarding, Today,
   Plan, Workout Detail, Progress, Settings) against the verified domain services
   — see `UX_SPEC.md`.
3. **Wire the notification bridge** — `UNUserNotificationCenter` adapter over the
   tested `NotificationPlanner` (rolling ≤64 window, cancellation on completion,
   deep links).
4. **UI tests & accessibility** — XCUITest for the core flows plus Dynamic Type
   and VoiceOver identifier checks (see `QA_CHECKLIST.md`).
5. **Capture screenshots / preview snapshots** for the deliverables list.
6. **Release 2** — HealthKit + Apple Watch + Widgets, each behind its protocol,
   with **migration tests** added before any schema change (see `CHANGELOG.md`,
   `CAPABILITIES.md`).
