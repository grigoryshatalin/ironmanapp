# PRIVACY.md — Endurance

Endurance is built privacy-first. **In Release 1, the app is entirely
on-device**: no analytics, no advertising SDKs, no third-party trackers, no
account, and no network calls. This document describes exactly what data exists,
where it lives, and what (if anything) ever leaves your device.

A short version of this statement is also shown inside the app (Settings →
About → Privacy).

---

## What data the app holds

All data is information **you** create or configure:

- **Your plan setup** — start/race date, race name and location, unit preference,
  preferred long-session and rest days, default workout times.
- **Your schedule** — the calendar-mapped workouts derived from the bundled plan.
- **Your training records** — completions, actual duration/distance, perceived
  exertion, fatigue/soreness, notes, and the modification history (skip,
  reschedule, shorten, replace).
- **Your notification choices** — which reminder categories are enabled and their
  times.

The 36-week training plan itself is bundled **content** (read-only reference
data), not personal information.

## Where it is stored

- On-device, in the app's local **SwiftData** store.
- A small "today" summary (`SharedTodaySnapshot`) is written to the app's private
  **App Group** container so future widgets and the Apple Watch app can read it
  cheaply. This container is part of your device and is not uploaded.

Nothing is stored on any Endurance server, because there is no Endurance server.

## Permissions

Endurance requests only what a feature needs, and only when you choose to use it.

| Permission | Release | Why | If you decline |
|---|---|---|---|
| **Notifications** | 1 | Local workout / preparation / fueling / recovery / weekly-review reminders. | The app is fully usable. Reminders are opt-in **per category**, and the system prompt appears only after you enable at least one category (per App Store Review Guideline 4.5.4, notifications are never required to use the app). |
| **HealthKit** | 2 (later) | Import completed workouts and, with separate permission, write your Endurance workouts. | Everything works without it; you log sessions manually. |
| **Location (When In Use)** | 3 (later) | Weather-aware advisories and course profiles. | Requested only if you turn those features on; you can enter locations manually instead. |

Release 1 requests **only** the Notifications permission. HealthKit and Location
are architected but not enabled in Release 1.

## HealthKit behavior (Release 2 — designed now)

When HealthKit is added, it follows these rules:

- **On-device.** HealthKit data is processed on your device and is never uploaded
  outside an iCloud sync you explicitly enable.
- **Progressive authorization.** The app asks for specific data types only as the
  feature that needs them is used — never a blanket request.
- **Read status is opaque by design.** Apple does not tell apps whether *read*
  access was granted, and a denied read simply returns no data. Endurance
  therefore never infers "you denied this" from empty results — it degrades
  gracefully.
- **Never for advertising or profiling.** Health and fitness data is never used
  for advertising, marketing, or data mining, and is never shared with third
  parties (App Store Review Guideline 5.1.3).
- **Health data stays out of iCloud** except through the private, opt-in CloudKit
  sync you choose to enable.
- **Disconnecting HealthKit never deletes your local training history.**

## Exporting your data

- You can export your **plan** as JSON and your **history** as JSON or CSV from
  Settings → Data Management.
- Export is always **you-initiated**, through the standard iOS share sheet. The
  data leaves your device only to wherever *you* choose to send it (e.g. Files,
  Mail). Endurance does not transmit it anywhere on its own.

## Deleting your data

From Settings → Data Management you can:

- **Reset completion history** — clears your records, keeps your plan.
- **Reset the app** — returns to first-launch onboarding.
- **Delete all local data** — removes everything Endurance stored on the device.

Each destructive action requires an explicit native confirmation. Deleting the
app from iOS also removes all of its local data.

## Does any of my data leave the device?

- **Release 1: No.** The app makes no network requests and has no account.
- **Later, only if you opt in:** iCloud sync (your data to *your* private iCloud),
  Strava/Garmin import-export (to those accounts you connect), and WeatherKit
  (sends coarse location to Apple to fetch a forecast). Each of these is optional,
  clearly labeled, and off by default. Provider credentials (Strava/Garmin) are
  stored in the device Keychain, not in ordinary app storage.

## Medical and safety note

Endurance is a training **organizer**, not a medical device, and does not provide
diagnosis or medical advice. Training for a full-distance triathlon is demanding —
seek qualified professional guidance where appropriate, and do not ignore pain,
illness, dizziness, chest symptoms, or unusual fatigue. Where required (App Store
policy effective 2026-03-26 for Health & Fitness apps in the US/UK/EEA), the
non-medical-device status is declared in App Store Connect at submission.
