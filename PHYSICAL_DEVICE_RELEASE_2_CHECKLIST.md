# Physical Device Checklist — Release 2

Everything that **cannot** be verified on the Simulator or by unit tests.

Nothing in this file is checked off. Each item is checked only after being
performed on the named hardware, by a person, with the result recorded.

## Legend

| Mark | Meaning |
|---|---|
| ✅ sim | Verified on the iOS Simulator |
| ✅ unit | Verified by automated tests with an injected fake |
| ⛔ iPhone | Requires a physical iPhone |
| ⛔ Watch | Requires a paired Apple Watch |

---

## A. Outstanding Release 1 gate

This was never closed and remains **mandatory before any public distribution**.

| Check | Status |
|---|---|
| Notification permission prompt appears and is honoured | ⛔ iPhone |
| A scheduled reminder is delivered at the right time | ⛔ iPhone |
| Reminders are not duplicated across relaunches | ⛔ iPhone (logic ✅ unit) |
| Completing a session cancels its pending reminder | ⛔ iPhone (logic ✅ unit) |
| Moving a session regenerates its reminder | ⛔ iPhone (logic ✅ unit) |
| Changing the plan anchor regenerates reminders | ⛔ iPhone (logic ✅ unit) |
| Tapping a notification deep-links to the right session | ⛔ iPhone (parsing ✅ unit) |
| Behaviour across reboot, Airplane Mode, time-zone change, DST | ⛔ iPhone |

---

## B. HealthKit — Stage 2 (import)

| Check | Status |
|---|---|
| Entitlement is accepted and the app launches signed | ⛔ iPhone |
| Authorization sheet appears with our purpose strings | ⛔ iPhone |
| Sheet copy is accurate and readable | ⛔ iPhone |
| Denying every category leaves the app fully usable | ⛔ iPhone (state ✅ unit) |
| Granting some categories does not break import | ⛔ iPhone |
| Anchored query returns real workouts | ⛔ iPhone |
| Anchor persists — second launch does not rescan | ⛔ iPhone (cursor ✅ unit) |
| Real swim/bike/run map to the right sports | ⛔ iPhone (table ✅ unit) |
| An unmapped activity (e.g. yoga) is skipped | ⛔ iPhone (✅ unit) |
| Editing a workout in Health surfaces as an update | ⛔ iPhone (✅ unit) |
| Deleting a workout in Health is reflected | ⛔ iPhone (✅ unit) |
| Health Inbox shows real activities with evidence | ⛔ iPhone |
| Confirming a match completes the planned session | ⛔ iPhone (✅ unit) |
| A rejected suggestion does not return | ⛔ iPhone (✅ unit) |
| Changing authorization in Settings is handled | ⛔ iPhone |

---

## C. HealthKit — Stage 3 (export)

| Check | Status |
|---|---|
| Enabling export triggers the **write** prompt only then | ⛔ iPhone |
| A manual completion is accepted by `HKWorkoutBuilder` | ⛔ iPhone |
| The workout appears correctly in the Health app | ⛔ iPhone |
| It is labelled as user-entered, not sensor-recorded | ⛔ iPhone |
| Distance and energy appear only when genuinely logged | ⛔ iPhone (✅ unit) |
| No fabricated heart rate / power / route is present | ⛔ iPhone (✅ unit) |
| Endurance metadata survives the round trip | ⛔ iPhone (✅ unit) |
| The exported workout does **not** return as an import | ⛔ iPhone (✅ unit) |
| A second export attempt does not write twice | ⛔ iPhone (✅ unit) |
| Rapid double tap writes once | ⛔ iPhone (✅ unit) |
| A denied write shows "Permission needed", not an error | ⛔ iPhone (✅ unit) |
| A failed save keeps the local completion and offers retry | ⛔ iPhone (✅ unit) |
| Force-quitting mid-save leaves a recoverable orphan | ⛔ iPhone (✅ unit) |
| Orphan recovery reconnects it on next launch | ⛔ iPhone (✅ unit) |
| A brick is refused with a clear explanation | ⛔ iPhone (✅ unit) |
| Deleting an Endurance workout removes it from Health | ⛔ iPhone (✅ unit) |
| Deleting refuses for a workout owned by another app | ⛔ iPhone (✅ unit) |
| Disconnect leaves Health workouts untouched | ⛔ iPhone (✅ unit) |
| Disconnect preserves local training history | ⛔ iPhone (✅ unit) |

---

## D. Stages 4–8 — not yet implemented

WorkoutKit scheduling, active workout recording, the watchOS app, Live
Activities, widgets, and App Intents are not built. Their hardware checks will be
added as each stage lands.

---

## E. Known simulator limitations

- Tests build with `CODE_SIGNING_ALLOWED=NO`, so the HealthKit entitlement is
  absent and the log shows
  `Missing com.apple.developer.healthkit entitlement`. **No simulator run has
  exercised the real HealthKit path.**
- The Simulator has no Health database worth importing from.
- Notification delivery timing and tap-through are not faithfully reproducible.
