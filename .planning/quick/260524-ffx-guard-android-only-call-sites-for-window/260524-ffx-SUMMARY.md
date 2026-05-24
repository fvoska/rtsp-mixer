---
phase: quick-260524-ffx
plan: 01
subsystem: infra
tags: [flutter, android, windows-desktop, platform-guards, foreground-service, audio-service, media-kit]

# Dependency graph
requires:
  - phase: 05-platform-scaffold (commit 05e7cce)
    provides: Windows desktop build target added to the Flutter project
provides:
  - Platform.isAndroid guards (with kIsWeb short-circuit) on every call site that reaches into flutter_foreground_task or audio_service
  - Internal no-op shortcuts in ForegroundServiceManager and audioHandlerProvider so callers don't need to repeat the check at every call site
affects: [windows-desktop-build, future-macos-desktop, future-windows-platform-work]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Canonical platform guard: `if (!kIsWeb && Platform.isAndroid) { ... }`. kIsWeb short-circuit MUST come first because `dart:io`'s `Platform` is unavailable on web."
    - "Two-layer guarding: outer call sites use the explicit guard; service surfaces (ForegroundServiceManager, audioHandlerProvider) also early-return internally so future call sites don't have to remember the check."

key-files:
  created: []
  modified:
    - lib/main.dart
    - lib/app.dart
    - lib/core/services/foreground_service.dart
    - lib/features/monitoring/services/audio_handler.dart
    - lib/features/monitoring/screens/monitoring_screen.dart

key-decisions:
  - "Two-layer guarding: ForegroundServiceManager / audioHandlerProvider are no-ops internally on non-Android, AND obvious external call sites (FlutterForegroundTask.* in main/app/screen) are gated explicitly. Avoids touching audio_player_provider.dart and avoids adding a PlatformService abstraction."
  - "kIsWeb short-circuit comes first in every guard so `dart:io`'s Platform is never read on web. Pattern is `!kIsWeb && Platform.isAndroid` — never bare `Platform.isAndroid`."
  - "audioHandlerProvider returns a constructed `MonitoringAudioHandler` without `AudioService.init` on non-Android. The handler's methods (`setCameraNames`, `setPlaying`, `setIdle`, `play`, `pause`, `stop`) push to inherited `BaseAudioHandler` streams, which is safe without platform init — so the caller in `_startMonitoringFlow` needs no extra guard."
  - "Left `startCallback`, `MonitoringTaskHandler`, and `_onTaskData` definitions intact even though they're unreachable on non-Android — they compile fine, removing them would risk the Android path."

patterns-established:
  - "Pattern: When a Flutter plugin only ships an Android implementation, gate at the call site with `!kIsWeb && Platform.isAndroid` AND make any first-party wrapper class an internal no-op so future callers don't have to remember the guard."
  - "Pattern: Conditional widget wrapping. To skip an Android-only inherited-widget wrapper (e.g. `WithForegroundTask`), extract the child into a local `Widget` and return `(!kIsWeb && Platform.isAndroid) ? Wrapper(child: app) : app`."

requirements-completed: [QUICK-260524-ffx]

# Metrics
duration: 4min
completed: 2026-05-24
---

# Quick Task 260524-ffx: Guard Android-Only Call Sites for Windows Desktop Compatibility

**Five files guarded with `!kIsWeb && Platform.isAndroid` so flutter_foreground_task and audio_service code paths are skipped on Windows desktop while Android control flow stays byte-for-byte identical.**

## Performance

- **Duration:** ~4 min
- **Started:** 2026-05-24T09:11:04Z
- **Completed:** 2026-05-24T09:14:21Z
- **Tasks:** 3
- **Files modified:** 5

## Accomplishments

- ForegroundServiceManager public API (`init`, `start`, `updateNotification`, `stop`, `isRunning`) early-returns on non-Android — callers can keep invoking it unconditionally.
- `audioHandlerProvider` now returns a valid `MonitoringAudioHandler` without calling `AudioService.init` on non-Android; the handler's methods become safe no-ops via inherited `BaseAudioHandler` streams.
- Direct `FlutterForegroundTask` call sites in `main.dart` (initCommunicationPort), `app.dart` (addTaskDataCallback / removeTaskDataCallback / WithForegroundTask wrapper), and `monitoring_screen.dart` (permission requests) are all gated.
- `flutter analyze` on the full project reports zero issues. media_kit playback paths are untouched on every platform.

## Task Commits

Each task was committed atomically:

1. **Task 1: Make ForegroundServiceManager and audioHandlerProvider no-ops on non-Android** — `ae8b4ca` (feat)
2. **Task 2: Guard direct FlutterForegroundTask calls in main.dart and app.dart** — `c8ce6dc` (feat)
3. **Task 3: Guard permission requests and MediaSession wiring in MonitoringScreen** — `92d49fe` (feat)

## Files Created/Modified

- `lib/core/services/foreground_service.dart` — added `dart:io Platform` + `kIsWeb` imports; every public `ForegroundServiceManager` method early-returns on non-Android (`init`/`start`/`updateNotification`/`stop` return void; `isRunning` returns `Future.value(false)`). `startCallback` and `MonitoringTaskHandler` left untouched (never invoked on non-Android because `startService` is gated above).
- `lib/features/monitoring/services/audio_handler.dart` — added platform imports; `audioHandlerProvider` skips `AudioService.init` on non-Android but still returns a constructed `MonitoringAudioHandler`. `MonitoringAudioHandler` body unchanged.
- `lib/main.dart` — added platform imports; wrapped `FlutterForegroundTask.initCommunicationPort()` in the canonical guard. `ForegroundServiceManager.init()` left as an unconditional call (its body is now self-guarding).
- `lib/app.dart` — added platform imports; wrapped `FlutterForegroundTask.addTaskDataCallback` (in `initState`) and `removeTaskDataCallback` (in `dispose`) symmetrically; extracted `MaterialApp.router(...)` to a local `Widget app` and replaced `WithForegroundTask(child: ...)` with a conditional return.
- `lib/features/monitoring/screens/monitoring_screen.dart` — added platform imports; wrapped the existing `try { checkNotificationPermission / requestNotificationPermission / isIgnoringBatteryOptimizations / requestIgnoreBatteryOptimization } catch (e) { ... }` block in `_maybeAutoResume` inside the platform guard, keeping the inner try/catch per CLAUDE.md "streams must never break".

## Decisions Made

- **Two-layer guards over a PlatformService abstraction.** The plan explicitly forbade a new abstraction layer. Making `ForegroundServiceManager` and `audioHandlerProvider` self-guarding means the existing 3 call sites in `audio_player_provider.dart` (and any future ones) don't need touching. The explicit call-site guards in `main`/`app`/`screen` are for places that talk to `FlutterForegroundTask` directly (no manager wraps `initCommunicationPort`, `addTaskDataCallback`, or `WithForegroundTask`).
- **kIsWeb first.** Every guard is `!kIsWeb && Platform.isAndroid`. Reading `Platform.isAndroid` on web would attempt to import `dart:io`, which throws at compile time on the web target. Short-circuiting on `kIsWeb` prevents that.
- **Kept the `flutter_foreground_task` imports in all five files.** The package is a pure Dart library wrapper on Windows — it compiles, it just doesn't function. Removing the imports would force a refactor of the `MonitoringTaskHandler` and `WithForegroundTask` type references. Per CLAUDE.md "prefer degraded functionality over crash", leaving the imports and gating execution is the minimal change.
- **Left `_onTaskData` callback body intact.** The callback is registered only inside the Android guard, so on Windows it's compiled-but-unreachable code. The two `ForegroundServiceManager.updateNotification(...)` calls inside it are no-ops via Task 1 anyway.

## Deviations from Plan

None — plan executed exactly as written. All three tasks landed with the exact files, guards, and patterns specified.

## Issues Encountered

None. The plan was precise about the canonical guard pattern, the import block to add, and which call sites required external vs. internal guards.

## User Setup Required

None — no external service configuration. **One manual verification step remains the user's responsibility** (recorded as a follow-up in the next section).

## Manual Verification Follow-up (REQUIRED)

`flutter analyze` passes cleanly on Linux/WSL, which proves compile-time correctness for the Windows target (Flutter's analyzer evaluates web/io platform conditionals statically). However, runtime verification cannot be done from WSL:

- **Windows desktop runtime check:** On a Windows machine, run `flutter build windows` and `flutter run -d windows`. Confirm:
  - App launches without throwing on missing plugin implementations.
  - Login flow + camera list + media_kit audio playback all work.
  - No `flutter_foreground_task` / `audio_service` runtime errors appear in the console.
- **Android regression check:** On an Android device, confirm:
  - Monitoring still starts via the Monitor tab.
  - The foreground service notification appears with Pause/Stop buttons.
  - Lock-screen MediaSession controls (play/pause/stop) still work.
  - Notification button taps still flow through `_onTaskData` → `audioPlayerProvider`.

## Verification Evidence

- `flutter analyze` (full project): **0 errors, 0 warnings** (`No issues found! (ran in 11.1s)`)
- `grep -l "Platform.isAndroid"` across the 5 target files: **5 matches** (expected: 5)
- `grep "Platform.isAndroid" lib/` filtered to lines lacking `kIsWeb`: **0 matches** (expected: 0)
- `grep -c "ForegroundServiceManager" lib/features/monitoring/providers/audio_player_provider.dart`: **3** (expected: 3 — file untouched)

## Self-Check: PASSED

All claimed artifacts verified to exist and contain the expected guard pattern. All three task commits exist in `git log --oneline`:

```
92d49fe feat(260524-ffx): guard FlutterForegroundTask permission calls in MonitoringScreen
c8ce6dc feat(260524-ffx): guard direct FlutterForegroundTask calls in main.dart and app.dart
ae8b4ca feat(260524-ffx): make ForegroundServiceManager and audioHandlerProvider no-ops on non-Android
```

---
*Quick task: 260524-ffx*
*Completed: 2026-05-24*
