# Known Limitations & Next Steps — Endurance

Deliverables §29 (16) known limitations and (17) next steps. Honest status of the
project as of 2026‑07‑25.

---

## Known limitations

### Build status
The app now **builds and runs**. On Xcode 26.6 / iOS 26.5 SDK:

- ✅ `EnduranceDomain` + the generated 36‑week plan: **57 tests passing**, zero
  warnings, plan JSON byte‑reproducible.
- ✅ The **SwiftUI iOS app compiles clean** (0 errors, 0 warnings) and **launches
  on the iOS 26.5 Simulator**; its 4 unit tests and 2 UI tests pass.
- ⏳ The **watchOS app, widgets, and App Intents** are architected but not yet
  built — they are Release 2.

Reproduce from a clean machine:
```bash
brew install xcodegen
xcodegen generate
xcodebuild test -project Endurance.xcodeproj -scheme Endurance \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```
Note that Xcode 26 ships **without** iOS platform support; a one‑time
`xcodebuild -downloadPlatform iOS` (~8 GB) is required before any iOS
destination resolves.

### Not yet verified
- **Physical iPhone.** Everything to date is Simulator‑only.
- **Persistence across relaunch.** Completion and rescheduling are written
  through `WorkoutStore` to SwiftData and unit‑tested at the domain level, but
  the relaunch round trip (§31) has not been exercised on device.
- **Notification delivery.** Identifier stability, cancellation, regeneration and
  the ≤64 budget are unit‑tested in `NotificationPlanner`; actual delivery,
  deep‑link taps, and non‑duplication have not been observed on a device.
- **Accessibility and appearance passes.** Dynamic Type, VoiceOver, Dark Mode,
  Reduce Motion and Increased Contrast from `QA_CHECKLIST.md` are unrun.
- **Screenshots** cover onboarding only (`docs/screenshots/`); the remaining
  screens need captures once onboarding can be driven end to end.

### Gaps against the brief
- **No accessibility identifiers** anywhere (§20, §23). This also caps the UI
  tests at weak assertions — `testOnboardingIsPresentOnFreshInstall` currently
  passes if it finds *either* onboarding *or* the Today tab.
- **No String Catalog; strings are hard‑coded** (§28.18 explicitly requires
  localization from the start). Cheapest to fix now, at ~1,900 lines, rather
  than after the watch app and widgets land.
- **No haptics** (§5) — zero `sensoryFeedback` usages.
- **App icon is a placeholder** — `ICON_SPEC.md` is written, the asset slot is
  empty (§25).
- **Plan filtering** (§10) and **interval check‑off** (§9) are supported by the
  data model but absent from the UI.

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

1. **Add accessibility identifiers** across onboarding, Today, and the sheets.
   This is a §20 release requirement in its own right, and it is the blocker on
   every UI test above smoke level — the current tests cannot assert what screen
   they are on.
2. **Drive onboarding end to end in a UI test**, then assert the real §31
   behaviours: onboarding yields a usable schedule, and completion plus
   rescheduling survive relaunch.
3. **Introduce a String Catalog** and move user‑facing strings into it before the
   codebase grows (§28.18).
4. **Run the `QA_CHECKLIST.md` matrix** — Dark Mode, largest Dynamic Type,
   VoiceOver, Reduce Motion, small/large iPhone — and capture screenshots of each
   screen for the deliverables list.
5. **Verify on a physical iPhone**, including notification delivery and
   deep‑link taps, which the Simulator exercises only partially.
6. **Close the remaining §27 MVP gaps** — haptics, app‑icon art, plan filtering,
   interval check‑off, and the long‑session/rest‑day remapping transform.
7. **Release 2** — HealthKit + Apple Watch + Widgets, each behind its protocol,
   with **migration tests** added before any schema change (see `CHANGELOG.md`,
   `CAPABILITIES.md`).
