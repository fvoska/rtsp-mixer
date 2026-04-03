# Phase 3: Android Background Operation - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-03
**Phase:** 03-android-background-operation
**Areas discussed:** Notification content, Screen-off behavior, Battery optimization UX, Service architecture
**Mode:** --auto (all decisions auto-selected)

---

## Service Architecture

| Option | Description | Selected |
|--------|-------------|----------|
| flutter_foreground_task + audio_service | Both packages complement: foreground_task for service lifecycle, audio_service for MediaSession | ✓ |
| flutter_foreground_task only | Simpler, but no lock screen / media notification controls | |
| audio_service only | Has background audio but less robust service lifecycle management | |

**User's choice:** [auto] flutter_foreground_task + audio_service (recommended default)
**Notes:** Per CLAUDE.md technology stack recommendation. Both packages listed as complementary.

---

## Notification Content

| Option | Description | Selected |
|--------|-------------|----------|
| Camera names + status with play/pause | Shows monitoring status, single toggle action | ✓ |
| Minimal "Monitoring active" text | Simple but less informative | |
| Full controls (play/pause/volume per camera) | Too complex for notification area | |

**User's choice:** [auto] Camera names + status with play/pause (recommended default)
**Notes:** Tap opens app to monitoring screen for full controls.

---

## Screen-Off Behavior

| Option | Description | Selected |
|--------|-------------|----------|
| Auto-disable video, keep audio | Video suspends on background/screen-off, audio uninterrupted | ✓ |
| Keep video running | Wastes battery, unnecessary when screen is off | |
| Pause everything, resume on wake | Defeats purpose of overnight monitoring | |

**User's choice:** [auto] Auto-disable video, keep audio (recommended default)
**Notes:** Matches CLAUDE.md constraint: "auto-suspends when app is backgrounded/screen off"

---

## Battery Optimization UX

| Option | Description | Selected |
|--------|-------------|----------|
| Document in README, no in-app prompt | Non-invasive, foreground service handles most devices | ✓ |
| In-app prompt to disable battery optimization | More reliable but invasive UX for v1 | |
| Ignore entirely | Risk of OEM killing the service overnight | |

**User's choice:** [auto] Document in README, no in-app prompt (recommended default)
**Notes:** OEM battery optimization flagged as Phase 3 risk in STATE.md. Real device testing will validate.

---

## Claude's Discretion

- flutter_foreground_task callback handler implementation details
- audio_service AudioHandler wiring to AudioPlayerNotifier
- Android notification channel configuration
- Gradle/Kotlin version bumps for compatibility

## Deferred Ideas

None — discussion stayed within phase scope
