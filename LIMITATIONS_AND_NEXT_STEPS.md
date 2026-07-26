# Known Limitations & Next Steps — Endurance

Deliverables §29 (16) known limitations and (17) next steps. Honest status of the
project as of 2026‑07‑26.

---

## Known limitations

### Build status
The app now **builds and runs**. On Xcode 26.6 / iOS 26.5 SDK:

- ✅ `EnduranceDomain` + the generated 36‑week plan: **69 tests passing**, zero
  warnings, plan JSON byte‑reproducible.
- ✅ The **SwiftUI iOS app compiles clean** (0 errors, 0 warnings) and runs on
  four simulator models. **4 app unit + 7 UI acceptance + 9 accessibility +
  9 screenshot tests** pass. See `RELEASE_1_VERIFICATION.md`.
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
- **Physical iPhone.** Everything to date is Simulator‑only. This is the single
  blocker on Release 1 sign‑off.
- **Notification delivery.** Identifier stability, non‑duplication, cancellation,
  regeneration and the ≤64 budget are unit‑tested in `NotificationPlanner`;
  actual delivery, the permission prompt, and tap‑through deep links require a
  device.
- **The manual‑only QA rows**: Airplane Mode, device reboot, a live time‑zone
  change, and a real DST boundary.

Now verified (previously listed here): persistence of completion and
rescheduling across terminate + relaunch, the Dynamic Type / VoiceOver / Dark
Mode / Reduce Motion / Increased Contrast / Differentiate Without Color / Bold
Text matrix, small and large iPhone layouts, and screenshots of every screen.

### Gaps against the brief

The 2026-07-26 refinement pass closed most of these. What remains:

- **On-device notification verification is outstanding** — the one blocker on
  Release 1 sign-off. No physical iPhone is connected. The decision layer
  (stable ids, no duplicates, cancellation, regeneration, rolling ≤64 window) is
  unit-tested; delivery, the permission prompt, and tap-through deep links are
  not. See `RELEASE_1_VERIFICATION.md` §4.1.
- **Interval check-off is session-scoped.** Ticks live in view state and reset
  when you leave the screen. Persisting them needs a schema bump plus migration
  fixtures (§28.22), so it was deliberately not half-shipped. It is optional and
  nothing depends on it.
- **Training zones remain RPE-only.** Heart-rate, power, pace and swim-pace zone
  editing is a later update. The app is fully usable without sensors.
- **Localization ships English only.** The infrastructure is in place — String
  Catalog, domain enums resolving through it, tests matching identifiers rather
  than text — so adding a language is now translation, not code.
- **Weekly progress is hidden on Today at accessibility text sizes.** Deliberate:
  the header otherwise consumed the whole screen and pushed every session off
  it. Progress remains on its own tab.

Closed in the refinement pass: accessibility identifiers (79), the permissive
smoke tests, the String Catalog, haptics, app-icon artwork, plan filtering,
screenshots, and the preferred long-ride / long-run / rest-day transform that
onboarding previously collected and ignored.

---

## Next steps (prioritized)

1. **Verify notifications on a physical iPhone** — the only item blocking
   Release 1. Connect a device, set a development team and unique bundle id,
   enable a reminder category with a near-future time, background the app, and
   confirm delivery, non-duplication, cancellation after completion, and that a
   tap opens the correct session.
2. **Run the manual columns of `QA_CHECKLIST.md`** that automation cannot cover:
   Airplane Mode, device reboot, live time-zone change, and a real DST boundary.
3. **Decide on persisting interval check-off.** If yes, bump the schema and add
   migration fixtures first (§28.22).
4. **Then** Release 2 — HealthKit, watchOS, WorkoutKit, Live Activities,
   Widgets, App Intents. `RELEASE_1_VERIFICATION.md` §7 confirms the current
   schema supports all of them without a destructive rewrite.
