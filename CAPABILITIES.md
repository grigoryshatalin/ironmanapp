# CAPABILITIES.md — Endurance

Entitlements and capabilities, by release, with what each requires. No capability
is enabled before its behavior + permission strings exist (brief §28.21).

## Legend
- **Free Apple ID** — works with a personal team, on‑device only.
- **Paid Program** — requires the $99/yr Apple Developer Program.
- **Apple review** — needs App Review / Beta App Review.
- **Provider** — needs external provider approval.
- **Backend** — needs a hosted server component.

## Release 1 (Core MVP)

| Capability / entitlement | Needed? | Tier | Notes |
|---|---|---|---|
| Local notifications (UserNotifications) | Yes | Free Apple ID | No entitlement; user permission at runtime. Interruption level `.active`. |
| App Groups (`group.<bundle>`) | Yes | Free Apple ID | Shared `SharedTodaySnapshot` for future widget/watch; created now so R2 needs no migration. |
| Background Modes → Background fetch/processing | Optional | Free Apple ID | Refresh the rolling notification window; app is correct without it. |
| Time Sensitive Notifications | **No** | — | Deliberately not requested for MVP (avoids entitlement dependency). |
| Critical Alerts | **No** | Apple review | Never requested — inappropriate for training reminders. |
| HealthKit | **No (R2)** | Paid Program | Capability + `NSHealthShareUsageDescription` / `NSHealthUpdateUsageDescription` added in R2. |

## Release 2 (Apple ecosystem)

| Capability | Tier | Notes |
|---|---|---|
| HealthKit (read/write, routes) | Paid Program | Progressive auth; read status is opaque — degrade gracefully. |
| WorkoutKit (`WorkoutScheduler`) | Paid Program | Separate authorization from HealthKit. Custom swimming needs iOS 18/watchOS 11. |
| Apple Watch app target | Paid Program | WatchConnectivity + durable transfers. |
| Widget extension (WidgetKit) | Free Apple ID | App Intents for configuration/interaction. |
| Live Activities (ActivityKit) | Free Apple ID | Active‑workout only; ends promptly. |
| Siri / App Intents | Free Apple ID | Shared domain services; confirmation for destructive actions. |

## Release 3 (Sync & intelligence)

| Capability | Tier | Notes |
|---|---|---|
| iCloud → CloudKit (private DB) | Paid Program | Document dev vs prod environments before enabling; migration tests must pass first. |
| Push Notifications (CloudKit subscriptions) | Paid Program | Only if silent sync pushes are added. |
| WeatherKit | Paid Program | Attribution required; advisory only. |
| Location (When In Use) | Free Apple ID | Requested only when weather/course features are enabled. |

## Release 4 (Coaching & external)

| Capability | Tier | Notes |
|---|---|---|
| Keychain Sharing | Free Apple ID | Store Garmin/Strava tokens securely. |
| Associated Domains | Paid Program | Universal links for plan/coach delivery. |
| Garmin Connect API | Provider + possibly Backend | Requires program approval; respect rate limits/consent. |
| Strava API | Provider + likely Backend | OAuth; client secret needs a secure exchange → minimal documented backend. |

## Cross‑cutting compliance

- **App Store medical‑device disclosure (effective 2026‑03‑26):** Health &
  Fitness apps must declare regulated medical‑device status in App Store Connect
  for US/UK/EEA. Endurance is a training organizer, not a medical device — the
  declaration must still be **completed** at submission. (Reported via 9to5Mac;
  verify against App Store Connect at submission time.)
- **App Review 4.5.4:** notifications are optional/opt‑in with opt‑out — satisfied.
- **App Review 5.1.3 / 1.4.1:** no health data for ads/profiling; disclose data
  collected; include a "consult a professional" reminder; no unsupported medical
  claims.
