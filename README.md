# Endurance

A native iPhone app for managing a complete **36‑week full‑distance triathlon
training plan**. It maps the plan onto real calendar dates from a start or race
date, shows exactly what to do today, sends calm local reminders, and lets you
complete, skip, shorten, replace, reschedule, and annotate sessions — fully
offline, with your data on device. It is built to feel like a first‑party Apple
app: quiet, legible, native, and accessible.

> **Not medical or coaching advice.** Endurance is an educational training
> organizer. Full‑distance triathlon places substantial stress on the body. Seek
> qualified professional guidance where appropriate, and stop for pain, illness,
> dizziness, chest symptoms, or unusual fatigue. The app does not diagnose.

> The product name **Endurance** is isolated in `project.yml` (`PRODUCT_NAME`)
> and `EnduranceDomain.productName`, so a rename touches two places.

---

## What is verified here vs. authored for Xcode

This repository was partly built in a headless environment with the Swift
toolchain but **without Xcode**, so it is honest about what is machine‑verified:

| Component | Status |
|---|---|
| `EnduranceDomain` (models, date engine, validator, notifications, progress, adaptation) | **Compiled + 57 tests passing** on the Swift 6 toolchain (`swift test`) |
| `EnduranceTrainingPlans` — generated 36‑week / 252‑day / 382‑workout plan JSON | **Generated, validated, reproducible, tested** |
| `enduranceplan` content generator | **Builds & runs** |
| SwiftUI app, watchOS, widgets (`Applications/`) | **Authored for Xcode 26** — compiled in Xcode, not in this environment |

The riskiest logic (DST/leap‑year date math, the 64‑notification budget, plan
validation, unit conversion, progress, export round‑trips) lives in the
Foundation‑only domain layer precisely so it can be tested without Xcode.

## Repository layout

```
ironmanapp/
  EndurancePackages/          Swift package — the shared, testable core
    Sources/
      EnduranceDomain/        Foundation-only: models, engines, services
      EnduranceTrainingPlans/ Bundled + generated plan JSON, loader
      enduranceplan/          Build-time plan generator (CLI)
    Tests/EnduranceDomainTests/
  Applications/               SwiftUI app + watch + widgets (built by Xcode)
  project.yml                 XcodeGen spec — assembles the Xcode targets
  DECISIONS.md  DATA_SCHEMA.md  EXPANSION_ARCHITECTURE.md  CAPABILITIES.md
  TRAINING_SOURCES.md  PRIVACY.md  QA_CHECKLIST.md  UX_SPEC.md  CHANGELOG.md
```

## Run the domain tests (no Xcode required)

```sh
cd EndurancePackages
swift test
```

## Regenerate the bundled 36‑week plan

The plan is generated deterministically and validated; the JSON is committed. To
rebuild it (e.g. after editing `PlanGenerator`):

```sh
cd EndurancePackages
swift run enduranceplan
# → Sources/EnduranceTrainingPlans/Resources/Endurance36Week.json
```

Output is byte‑reproducible; a test asserts the committed JSON stays in sync.

---

## Local development (the app)

1. Install **Xcode 26** (targets the iOS 26 SDK). Minimum deployment is iOS 18 /
   watchOS 11.
2. Install the project generator: `brew install xcodegen`.
3. Generate the project (the `.xcodeproj` is git‑ignored and always generated):
   ```sh
   xcodegen generate
   open Endurance.xcodeproj
   ```
4. Select the **Endurance** scheme. In *Signing & Capabilities*, choose your
   **development team** and set a unique **bundle identifier**
   (e.g. `com.yourname.endurance`).
5. **Run in Simulator:** pick an iPhone simulator and press ⌘R.
6. **Run on a connected iPhone:** plug in your device, select it as the run
   destination, and press ⌘R. On the first run, **enable Developer Mode** on the
   device: *Settings → Privacy & Security → Developer Mode → On*, then reboot and
   confirm. Trust the developer certificate under *Settings → General → VPN &
   Device Management* if prompted.
7. **Test local notifications:** enable one or more reminder categories in
   Onboarding/Settings and grant permission. Because reminders fire at scheduled
   times, either set near‑future times, background the app, or use the
   Simulator's Notification Center to observe delivery. The app refreshes its
   rolling notification window on launch and foreground.

## Personal installation (free Apple ID)

You can sign and install directly from Xcode with a free Apple ID ("personal
team"). Note that a free‑provisioned build **expires after ~7 days** and must be
re‑signed and re‑installed from Xcode. **An unsigned iOS app cannot be installed
permanently** — some form of signing is always required.

## TestFlight distribution

TestFlight requires the paid **Apple Developer Program** ($99/yr).

1. Create the app record in **App Store Connect** (matching your bundle id).
2. In Xcode: *Product → Archive*, then **Distribute App → TestFlight** to upload
   the build.
3. **Internal testing:** add up to **100** App Store Connect team members — no
   Beta App Review; builds are usually available within minutes.
4. **External testing:** up to **10,000** testers via email or a public link; the
   **first build of each version requires Beta App Review**.
5. Builds **expire 90 days** after upload. To update, increment the build number,
   archive, and upload a new build; testers are notified.

See `CAPABILITIES.md` for which capabilities need the paid program, Apple review,
or external‑provider approval, and `QA_CHECKLIST.md` for the manual test matrix.
