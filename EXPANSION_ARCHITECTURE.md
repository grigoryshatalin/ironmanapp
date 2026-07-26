# EXPANSION_ARCHITECTURE.md — Endurance

How the Release‑1 foundations carry **every** feature on the full‑product roadmap
(brief §28) without destructive rewrites. The rule: the MVP contains the
architectural seams for later releases, even where the user‑facing feature ships
later.

---

## 1. Module map (Swift packages + app targets)

```
ironmanapp/
  EndurancePackages/                 ← one SwiftPM package, many library targets
    Sources/
      EnduranceDomain/     (R1) Foundation-only. Models, engines, service PROTOCOLS.
      EndurancePersistence/(R1) SwiftData models + repositories (adapters).
      EnduranceTrainingPlans/(R1) Bundled plan JSON + loader.
      EnduranceUI/         (R1) SwiftUI design system + shared views.
      EnduranceHealth/     (R2) HealthKit + WorkoutKit behind protocols.
      EnduranceWorkouts/   (R2) Active-workout session logic (watch + phone).
      EnduranceSync/       (R3) CloudKit sync + conflict resolution.
      EnduranceWeather/    (R3) WeatherKit advisory engine.
      EnduranceIntegrations/(R4) Garmin/Strava behind ExternalFitnessProvider.
      EnduranceIntents/    (R2) App Intents calling domain services.
  Applications/
    iOS/        (R1) main app target
    watchOS/    (R2) companion
    Widgets/    (R2) WidgetKit + Live Activity extension
  project.yml   ← XcodeGen: assembles the targets, entitlements, app groups
```

The **domain layer never imports SwiftUI/HealthKit/WidgetKit**. Every optional
capability sits behind a protocol in `EnduranceDomain` and is implemented in its
own package, so *disconnecting any optional service cannot break the core*
(brief §28.23). This is already true today: the core builds and its 51 tests run
with no UI, Health, or notification frameworks present.

## 2. Shared domain model & persistence

- One set of value types (`ScheduledWorkout`, `WorkoutCompletion`, …) is the
  lingua franca for phone, watch, widgets, intents, and sync. SwiftData `@Model`
  classes in `EndurancePersistence` map 1:1 to these and expose them via
  repositories, so **no view or extension touches the store directly** and swaps
  (e.g. adding CloudKit) are localized.
- **Migration is a first‑class concern (brief §28.22):** every schema bump ships
  with migration fixtures representing prior versions and passing migration
  tests, before any model change lands. `schemaVersion` exists on both plan
  content and the export envelope. We never tell users to reinstall.

## 3. Shared workout identity (brief §28.2)

`WorkoutIdentity` already separates `planID` / `templateID` /
`scheduledWorkoutID` / `executionID` / `externalReferences`. This is the single
mechanism that keeps a workout stable across reschedule, iCloud sync, HealthKit
import, watch completion, Garmin/Strava import, plan updates, device
replacement, and export/re‑import. External systems attach via
`ExternalWorkoutReference` (provider + provider id + sync timestamps), which is
also the duplicate‑detection key.

## 4. Service protocols (the seams)

Defined/assumed in the domain, implemented per release:

| Protocol | Release | Purpose |
|---|---|---|
| `PlanRepository`, `WorkoutRepository` | R1 | persistence access |
| `NotificationScheduling` (wraps `NotificationPlanner`) | R1 | UN center bridge |
| `HealthService` | R2 | HealthKit read/write, progressive auth |
| `WorkoutKitConverting` | R2 | structured‑workout export to Watch |
| `ExternalFitnessProvider` | R4 | Garmin/Strava/... uniform interface |
| `SyncEngine` | R3 | CloudKit push/pull + conflict resolution |
| `WeatherProvider` | R3 | WeatherKit advisory data |

Because App Intents, widgets, and the watch app call these same services, there
is **no duplicated business logic** (brief §28.17).

## 5. App Groups & shared snapshots (brief §28.19–28.20)

- An **App Group** container holds a compact `SharedTodaySnapshot` (already
  defined) that widgets, intents, and the watch read without opening SwiftData.
  The full mutable store is **not** exposed indiscriminately to extensions.
- Background work (widget refresh, sync drain, weather cache, notification
  window refresh) is **idempotent** and the app stays correct if it never runs.
  Local user actions are durable immediately.

## 6. Per‑release fit

- **R1 Core** — everything above's R1 rows; the verified domain core exists now.
- **R2 Apple ecosystem** — `EnduranceHealth` (HealthKit import/export dedup via
  `ExternalWorkoutReference`; WorkoutKit conversion with transparent fallback),
  `watchOS/` (durable WatchConnectivity + shared snapshot; queued offline
  completions), `Widgets/` (+ Live Activity via ActivityKit), `EnduranceIntents/`.
- **R3 Sync & intelligence** — `EnduranceSync` (CloudKit private DB; UUIDs +
  revision metadata + tombstones; field‑level merge, user‑visible resolution for
  destructive ambiguity — never blind last‑write‑wins); `EnduranceWeather`
  (advisory only, with reasoning + freshness); equipment mileage, race packing
  lists, course profiles, adaptive weekly recommendations (deterministic,
  explainable, confirmation‑gated). New entities are additive models.
- **R4 Coaching & external** — coach‑authored plans reuse the *same validated
  plan schema* + import validation; `ExternalFitnessProvider` keeps provider code
  out of the core; secrets in Keychain (+ minimal backend only if Strava token
  exchange requires it); full localization via String Catalogs.

## 7. Localization from day one (brief §28.18)

User‑facing UI strings go through String Catalogs; domain enums expose
`localizationKey`s rather than baked English. Distances/paces/temperatures format
via locale‑ and unit‑aware APIs (`UnitFormatter`). Bundled **plan content** ships
in English (the initial language) as data; translating it is additive and needs
no code change. Layouts avoid fixed widths and text‑in‑images; RTL supported.

## 8. What this buys us

Disconnecting HealthKit, the watch, Strava, Garmin, iCloud, or weather leaves a
fully functional offline training app — because each is an optional adapter
behind a protocol, and the tested core depends on none of them.
