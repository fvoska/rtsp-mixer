---
phase: quick-260524-ffx
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - lib/main.dart
  - lib/app.dart
  - lib/core/services/foreground_service.dart
  - lib/features/monitoring/services/audio_handler.dart
  - lib/features/monitoring/screens/monitoring_screen.dart
autonomous: true
requirements: [QUICK-260524-ffx]

must_haves:
  truths:
    - "flutter analyze passes with zero errors after the change"
    - "On Android, every existing foreground-service / MediaSession call still executes (no behavior change)"
    - "On non-Android platforms (Windows desktop in particular), code paths that touch flutter_foreground_task or audio_service are skipped instead of invoked"
    - "media_kit audio playback code paths remain untouched on every platform"
    - "Android-only code is gated at the call site or behind a single isAndroid early-return inside the manager — no new abstraction layer"
  artifacts:
    - path: "lib/core/services/foreground_service.dart"
      provides: "ForegroundServiceManager with internal isAndroid guards so public API is a no-op on non-Android"
      contains: "Platform.isAndroid"
    - path: "lib/features/monitoring/services/audio_handler.dart"
      provides: "audioHandlerProvider returning a non-Android no-op handler when not on Android"
      contains: "Platform.isAndroid"
    - path: "lib/main.dart"
      provides: "Guarded FlutterForegroundTask.initCommunicationPort and ForegroundServiceManager.init"
      contains: "Platform.isAndroid"
    - path: "lib/app.dart"
      provides: "Guarded FlutterForegroundTask task data callbacks and conditional WithForegroundTask wrapper"
      contains: "Platform.isAndroid"
    - path: "lib/features/monitoring/screens/monitoring_screen.dart"
      provides: "Guarded permission checks and audioHandlerProvider read in _maybeAutoResume/_startMonitoringFlow"
      contains: "Platform.isAndroid"
  key_links:
    - from: "all 5 guarded files"
      to: "dart:io Platform.isAndroid + package:flutter/foundation.dart kIsWeb"
      via: "kIsWeb short-circuit before reading Platform.isAndroid"
      pattern: "(!kIsWeb && Platform.isAndroid)"
---

<objective>
Make the codebase compile and run on Windows desktop by guarding all flutter_foreground_task and audio_service call sites with `Platform.isAndroid` (with a `kIsWeb` short-circuit so `dart:io` is never imported on web).

Purpose: The repo just gained a Windows build target (commit 05e7cce). flutter_foreground_task and audio_service don't support Windows, so any direct call would either fail to compile or crash at runtime. Android must keep behaving identically; on Windows the foreground service / MediaSession layer is silently skipped while media_kit audio playback keeps working.

Output: 5 guarded files. No new abstraction layer, no package removals, no Android behavior change. `flutter analyze` passes.
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
@$HOME/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@CLAUDE.md
@lib/main.dart
@lib/app.dart
@lib/core/services/foreground_service.dart
@lib/features/monitoring/services/audio_handler.dart
@lib/features/monitoring/screens/monitoring_screen.dart
@pubspec.yaml

<interfaces>
Existing public surfaces being guarded (extracted from current code — do not change shape):

From lib/core/services/foreground_service.dart:
- `class ForegroundServiceManager`
  - `static void init()` — idempotent, sets `_initialized`
  - `static Future<void> start(List<String> cameraNames)`
  - `static Future<void> updateNotification({required String text, String title = 'Baby Monitor Active', List<NotificationButton>? notificationButtons})`
  - `static Future<void> stop()`
  - `static Future<bool> get isRunning`
- Top-level `@pragma('vm:entry-point') void startCallback()` — Android entry point; OK to leave defined on all platforms (never invoked on Windows because `FlutterForegroundTask.startService` is never called)
- `class MonitoringTaskHandler extends TaskHandler` — only constructed inside `startCallback`, fine to leave compile-only on non-Android (the import still exists)

From lib/features/monitoring/services/audio_handler.dart:
- `class MonitoringAudioHandler extends BaseAudioHandler`
  - `void setCameraNames(List<String> cameraNames)`
  - `void setPlaying()`
  - `void setIdle()`
  - `Future<void> play() async` (override)
  - `Future<void> pause() async` (override)
  - `Future<void> stop() async` (override)
- `final audioHandlerProvider = FutureProvider<MonitoringAudioHandler>(...)` — currently always calls `AudioService.init`. Callers `await ref.read(audioHandlerProvider.future)` then call `setCameraNames` / `setPlaying`.

Call sites that need direct guards (cannot be hidden behind the manager):
- `lib/main.dart:12` — `FlutterForegroundTask.initCommunicationPort()`
- `lib/main.dart:16` — `ForegroundServiceManager.init()` (could be made internally a no-op, but guard at call site for clarity / parity)
- `lib/app.dart:22` — `FlutterForegroundTask.addTaskDataCallback(_onTaskData)` in `initState`
- `lib/app.dart:27` — `FlutterForegroundTask.removeTaskDataCallback(_onTaskData)` in `dispose`
- `lib/app.dart:79` — `WithForegroundTask(child: MaterialApp.router(...))` in `build` — on non-Android, return the `MaterialApp.router` directly (no wrapper)
- `lib/features/monitoring/screens/monitoring_screen.dart:55-68` — the permission-request block (`checkNotificationPermission`, `requestNotificationPermission`, `isIgnoringBatteryOptimizations`, `requestIgnoreBatteryOptimization`)
- `lib/features/monitoring/screens/monitoring_screen.dart:85-93` — `ForegroundServiceManager.start(names)` + `audioHandlerProvider` future read + `handler.setCameraNames` + `handler.setPlaying`

Cross-platform foundation imports to use:
- `import 'dart:io' show Platform;`
- `import 'package:flutter/foundation.dart' show kIsWeb;`
- Standard guard pattern (write exactly this — never bare `Platform.isAndroid` because `dart:io` is unavailable on web):
  ```dart
  if (!kIsWeb && Platform.isAndroid) { ... }
  ```
</interfaces>
</context>

<tasks>

<task type="auto">
  <name>Task 1: Make ForegroundServiceManager and audioHandlerProvider no-ops on non-Android</name>
  <files>lib/core/services/foreground_service.dart, lib/features/monitoring/services/audio_handler.dart</files>
  <action>
Guard the two service surfaces so callers don't need to repeat the check at every call site.

In `lib/core/services/foreground_service.dart`:
- Add `import 'dart:io' show Platform;` and `import 'package:flutter/foundation.dart' show kIsWeb;` near the existing imports.
- At the top of each of these `ForegroundServiceManager` public methods, add an early return when `kIsWeb || !Platform.isAndroid` (write the condition as `if (kIsWeb || !Platform.isAndroid) return;` and, for `isRunning`, `if (kIsWeb || !Platform.isAndroid) return false;`):
  - `init()` — early return BEFORE setting `_initialized` (so a future Android-only build that flips platform doesn't get stuck initialized=false; this is a defensive choice but per CLAUDE.md "degraded functionality over crash" — non-Android stays uninitialized forever, which is correct)
  - `start(List<String>)` — log `appLog('FGS', 'Foreground service unsupported on this platform — skipping start')` and return
  - `updateNotification({...})` — silent return (high-frequency caller; logging would spam)
  - `stop()` — silent return
  - `isRunning` getter — return `Future.value(false)`
- Do NOT modify `startCallback()` or `MonitoringTaskHandler` — they're never invoked on non-Android (because `startService` is gated above) and changing them adds risk for the Android path.
- Leave the `flutter_foreground_task` import in place; the package compiles on Windows as a Dart library (it just won't function), and removing the import would force a refactor.

In `lib/features/monitoring/services/audio_handler.dart`:
- Add `import 'dart:io' show Platform;` and `import 'package:flutter/foundation.dart' show kIsWeb;`.
- Modify the `audioHandlerProvider` body: on non-Android, return a `MonitoringAudioHandler(ref)` instance WITHOUT calling `AudioService.init`. The methods (`setCameraNames`, `setPlaying`, `setIdle`, `play`, `pause`, `stop`) all just push to `mediaItem` / `playbackState` streams (inherited from `BaseAudioHandler`) — those constructors don't require platform init, so they're safe to invoke on Windows as no-ops from the caller's perspective.
  ```dart
  final audioHandlerProvider = FutureProvider<MonitoringAudioHandler>((ref) async {
    final handler = MonitoringAudioHandler(ref);
    if (kIsWeb || !Platform.isAndroid) {
      appLog('AUDIO_SERVICE', 'MediaSession unsupported on this platform — skipping AudioService.init');
      return handler;
    }
    await AudioService.init(
      builder: () => handler,
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'baby_monitor_media',
        androidNotificationChannelName: 'Baby Monitor Media',
        androidNotificationOngoing: false,
        androidStopForegroundOnPause: true,
      ),
    );
    return handler;
  });
  ```
- Verify `BaseAudioHandler` is constructible without `AudioService.init` — if `flutter analyze` flags this as an issue, the fallback is to gate the FutureProvider to throw on non-Android and adjust the single caller in monitoring_screen.dart (Task 3) to skip the read instead. Prefer the no-op handler approach first.

Per CLAUDE.md "Defensive error handling — streams must never break": these guards make the foreground/MediaSession layer degrade silently. media_kit Players are untouched.
  </action>
  <verify>
    <automated>cd /home/fvoska/projects/personal/rtsp-mixer &amp;&amp; flutter analyze lib/core/services/foreground_service.dart lib/features/monitoring/services/audio_handler.dart</automated>
  </verify>
  <done>Both files import `dart:io` + `kIsWeb`. Every public `ForegroundServiceManager` method early-returns on non-Android. `audioHandlerProvider` skips `AudioService.init` on non-Android but still returns a handler. flutter analyze passes for these two files. No changes to Android code paths.</done>
</task>

<task type="auto">
  <name>Task 2: Guard direct FlutterForegroundTask calls in main.dart and app.dart</name>
  <files>lib/main.dart, lib/app.dart</files>
  <action>
Gate the call sites that use `FlutterForegroundTask` directly (not via the manager) and the `WithForegroundTask` widget wrapper.

In `lib/main.dart`:
- Add `import 'dart:io' show Platform;` and `import 'package:flutter/foundation.dart' show kIsWeb;`.
- Wrap line 12 (`FlutterForegroundTask.initCommunicationPort()`) in `if (!kIsWeb &amp;&amp; Platform.isAndroid)`.
- Leave `ForegroundServiceManager.init()` as-is — the manager itself is now a no-op on non-Android (Task 1), so calling it is safe. Do NOT remove the call.
- Keep `MediaKit.ensureInitialized()`, `AppLogger.instance.init()`, and `LocalNotificationsManager.init()` unguarded — none of them are Android-only (flutter_local_notifications supports Windows; media_kit is the whole point).

In `lib/app.dart`:
- Add `import 'dart:io' show Platform;` and `import 'package:flutter/foundation.dart' show kIsWeb;`.
- `initState()`: wrap `FlutterForegroundTask.addTaskDataCallback(_onTaskData);` in `if (!kIsWeb &amp;&amp; Platform.isAndroid)`.
- `dispose()`: wrap `FlutterForegroundTask.removeTaskDataCallback(_onTaskData);` in the same guard. (If `addTaskDataCallback` was skipped, `removeTaskDataCallback` would still be skipped — symmetric.)
- `build()`: replace the `WithForegroundTask(child: MaterialApp.router(...))` with a conditional. Extract the `MaterialApp.router(...)` into a local `Widget app = MaterialApp.router(...)` and return `(!kIsWeb &amp;&amp; Platform.isAndroid) ? WithForegroundTask(child: app) : app;`. This avoids referencing the `WithForegroundTask` widget at runtime on Windows.
- Leave `_onTaskData` and `_currentNotificationText` as-is — `_onTaskData` is only invoked by the (now-guarded) callback registration, so on Windows it's dead code that still compiles. The `ForegroundServiceManager.updateNotification(...)` calls inside `_onTaskData` are no-ops on non-Android via Task 1.

Per the "Do NOT change Android behavior" constraint: every guard uses `if (!kIsWeb &amp;&amp; Platform.isAndroid)` so the Android path is byte-for-byte identical to before.
  </action>
  <verify>
    <automated>cd /home/fvoska/projects/personal/rtsp-mixer &amp;&amp; flutter analyze lib/main.dart lib/app.dart</automated>
  </verify>
  <done>Both files import `dart:io` + `kIsWeb`. `FlutterForegroundTask.initCommunicationPort`, `addTaskDataCallback`, `removeTaskDataCallback`, and the `WithForegroundTask` wrapper are all gated. flutter analyze passes for these two files. Android control flow is unchanged (the guard evaluates true → original code runs).</done>
</task>

<task type="auto">
  <name>Task 3: Guard permission requests and MediaSession wiring in MonitoringScreen, then verify the full tree</name>
  <files>lib/features/monitoring/screens/monitoring_screen.dart</files>
  <action>
Gate the remaining direct `FlutterForegroundTask` permission calls and the `audioHandlerProvider` read in `MonitoringScreen`.

- Add `import 'dart:io' show Platform;` and `import 'package:flutter/foundation.dart' show kIsWeb;`.
- In `_maybeAutoResume()`:
  - Wrap the entire `try { ... } catch (e) { ... }` permission block (lines ~55-68: `checkNotificationPermission`, `requestNotificationPermission`, `isIgnoringBatteryOptimizations`, `requestIgnoreBatteryOptimization`) in `if (!kIsWeb &amp;&amp; Platform.isAndroid) { ... }`. Keep the existing try/catch inside the guard — per CLAUDE.md these must not crash.
- In `_startMonitoringFlow()`:
  - The call `await ForegroundServiceManager.start(names);` (line ~85) is already safe — Task 1 made the manager a no-op on non-Android. Leave it as-is.
  - The `was_monitoring` storage write (line ~86) and the `audioHandlerProvider` block (lines ~87-93) — keep the `audioHandlerProvider.future` await, because Task 1 made the provider return a handler without calling `AudioService.init` on non-Android. `handler.setCameraNames(names); handler.setPlaying();` will then push to the inherited streams as no-ops. No guard needed here.
  - Rationale for not guarding this block: per the "Do NOT add a new abstraction layer unless absolutely necessary" constraint, the handler itself being a no-op is simpler than adding `if (!kIsWeb &amp;&amp; Platform.isAndroid)` here.
- Leave `_videoSuspendedByLifecycle`, lifecycle callbacks, `_restoreVideoState`, `_toggleGlobalVideo`, `_toggleCameraVideo`, `_onStopPressed`, `_onRemoveCamera`, and the whole widget tree below unchanged — none of them touch flutter_foreground_task or audio_service directly.
- The call inside `_onStopPressed` -&gt; `stopMonitoringAndCleanup` reaches `ForegroundServiceManager.stop()` in `audio_player_provider.dart`, which is a no-op on non-Android via Task 1.

After editing this file, verify the WHOLE tree:
- Run `flutter analyze` on the entire project (not just this file). This is the load-bearing check: it must pass with zero errors. Warnings about unused imports of `dart:io` are unacceptable — only import `Platform` if used (which is true in every file we touched).
- Sanity-grep that audio_player_provider.dart wasn't accidentally edited (it should be unchanged because Task 1 made ForegroundServiceManager.updateNotification / stop calls inside it auto-skip on non-Android):
  ```
  grep -c "ForegroundServiceManager" lib/features/monitoring/providers/audio_player_provider.dart
  ```
  expect: 3 (matches the original count).

Document the Windows build verification as a manual step in the SUMMARY (cannot run `flutter build windows` from WSL).
  </action>
  <verify>
    <automated>cd /home/fvoska/projects/personal/rtsp-mixer &amp;&amp; flutter analyze 2>&amp;1 | tee /tmp/analyze-260524-ffx.log &amp;&amp; ! grep -E "error •" /tmp/analyze-260524-ffx.log</automated>
  </verify>
  <done>`monitoring_screen.dart` imports `dart:io` + `kIsWeb`. The permission-request block in `_maybeAutoResume` is wrapped in the platform guard. `flutter analyze` on the entire project shows zero errors. The 3 references to `ForegroundServiceManager` in `audio_player_provider.dart` are unchanged. Android control flow remains identical. SUMMARY notes that `flutter build windows` is a manual verification step the user must run on a Windows machine (can't run from WSL).</done>
</task>

</tasks>

<verification>
- `flutter analyze` exits with status 0 and reports zero errors (warnings about deprecated APIs that pre-existed are acceptable).
- Grep verifications:
  ```
  # Every guarded file uses the canonical pattern (kIsWeb short-circuit first)
  grep -l "Platform.isAndroid" lib/main.dart lib/app.dart lib/core/services/foreground_service.dart lib/features/monitoring/services/audio_handler.dart lib/features/monitoring/screens/monitoring_screen.dart | wc -l
  # expect: 5

  # No bare Platform.isAndroid without kIsWeb short-circuit (would crash on web)
  grep -rn "Platform.isAndroid" lib/ | grep -v "kIsWeb" | grep -v "^[^:]*://" | wc -l
  # expect: 0

  # audio_player_provider.dart was not touched
  grep -c "ForegroundServiceManager" lib/features/monitoring/providers/audio_player_provider.dart
  # expect: 3
  ```
- Manual verification (can't run from WSL — record as a follow-up for the user):
  - On a Windows machine: `flutter build windows` succeeds, app launches, login + camera list + audio playback all work, no flutter_foreground_task or audio_service runtime errors in the console.
  - On Android: regression-test that monitoring still starts, the foreground notification appears, the pause/stop buttons work, and the lock-screen MediaSession controls behave as before.
</verification>

<success_criteria>
- `flutter analyze` passes with zero errors on the full project.
- 5 files modified, all using the same `if (!kIsWeb && Platform.isAndroid)` guard pattern.
- No new files, no new abstraction layer (no `PlatformService` interface, no `Stub` classes — just call-site guards + two internal no-op shortcuts).
- No changes to: pubspec.yaml dependencies, Android code paths, media_kit code, anything in `audio_player_provider.dart`.
- SUMMARY flags `flutter build windows` as a manual verification step that requires a Windows host.
</success_criteria>

<output>
Create `.planning/quick/260524-ffx-guard-android-only-call-sites-for-window/260524-ffx-SUMMARY.md` when done. Note in the SUMMARY:
- The 5 files changed and exactly which lines/blocks were guarded.
- The decision to make `ForegroundServiceManager` and `audioHandlerProvider` internally no-op (avoids cluttering every caller) vs gating at every call site (rejected — would require touching audio_player_provider.dart).
- The manual follow-up: user must run `flutter build windows` on a Windows machine to confirm runtime success, and re-test Android to confirm no regression.
</output>
