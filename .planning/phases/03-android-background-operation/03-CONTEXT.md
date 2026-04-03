# Phase 3: Android Background Operation - Context

**Gathered:** 2026-04-03
**Status:** Ready for planning

<domain>
## Phase Boundary

Run the existing audio monitoring app as an Android foreground service that survives the screen turning off and the phone sitting on a nightstand charging overnight (8+ hours). The app must build and run on a physical Android device. No new monitoring features — this phase is purely about platform migration and background execution.

</domain>

<decisions>
## Implementation Decisions

### Service Architecture
- **D-01:** Use `flutter_foreground_task` for foreground service lifecycle (start/stop, persistent notification, keeps process alive). Use `audio_service` for MediaSession integration (lock screen controls, notification media actions). Both packages work together — foreground task keeps the service alive, audio_service provides the media notification.
- **D-02:** Players created by `AudioPlayerNotifier` continue running inside the foreground service. No need to move player management to a separate isolate — the existing architecture works within the foreground service context.

### Notification Content
- **D-03:** Persistent notification shows "Monitoring: [Camera1], [Camera2]" with current connection status.
- **D-04:** Single play/pause toggle action in the notification for quick stop/resume.
- **D-05:** Tapping the notification body opens the app to the monitoring screen.

### Screen-Off Behavior
- **D-06:** Video preview (if enabled) auto-disables when app is backgrounded or screen turns off. Audio continues uninterrupted. Video re-enables when user returns to the app.
- **D-07:** Wake lock (partial) acquired when monitoring starts to prevent CPU sleep. Released when monitoring stops.
- **D-08:** High-performance WiFi lock acquired to prevent WiFi throttling during screen-off. Critical for RTSP stream stability overnight.

### Battery Optimization
- **D-09:** No in-app battery optimization prompt for v1. Document known OEM issues (Samsung, Xiaomi aggressive killing) in project docs. Foreground service type + wake lock should handle most devices.

### Android Platform Setup
- **D-10:** Set `minSdk` to 21 (media_kit requirement), `targetSdk` to 34 (required for foreground service type declarations per Android 14+).
- **D-11:** Declare `foregroundServiceType="mediaPlayback"` in AndroidManifest.xml. Add required permissions: `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_MEDIA_PLAYBACK`, `WAKE_LOCK`, `INTERNET`, `ACCESS_NETWORK_STATE`.

### Claude's Discretion
- Specific flutter_foreground_task callback handler implementation
- How to wire audio_service's AudioHandler to the existing AudioPlayerNotifier
- Android notification channel configuration details
- Gradle/Kotlin version bumps needed for flutter_foreground_task 9.x compatibility

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Technology Stack
- `CLAUDE.md` §Recommended Stack > Background Execution — flutter_foreground_task and audio_service package details, versions, and rationale
- `CLAUDE.md` §Key Version Constraints — Flutter >= 3.22.0, Dart >= 3.4.0, Kotlin >= 1.9.10, Gradle >= 8.6.0, Android minSdk >= 21, targetSdk >= 34

### Package Documentation
- flutter_foreground_task on pub.dev (v9.2.2) — foreground service setup, notification config, callback handlers, two-way communication
- audio_service on pub.dev (v0.18.15) — AudioHandler, MediaSession, background audio, notification controls

### Existing Implementation
- `lib/features/monitoring/providers/audio_player_provider.dart` — AudioPlayerNotifier with full player lifecycle (start, stop, dispose, volume, mute, video toggle)
- `lib/features/monitoring/models/player_state.dart` — MonitoringState, CameraAudioState, CameraConnectionStatus models
- `android/app/build.gradle.kts` — current Android build config (needs minSdk/targetSdk adjustment)
- `android/app/src/main/AndroidManifest.xml` — bare manifest, needs permissions and foreground service declarations

### Related Constraints
- `CLAUDE.md` §Conventions > Defensive error handling — streams must never break, wrap non-critical ops in try/catch
- `CLAUDE.md` §media_kit FFmpeg build limitations — prebuilt FFmpeg limitations, vid=no for audio-only

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `AudioPlayerNotifier` — complete player lifecycle management, can be wrapped by foreground service callbacks
- `MonitoringState` / `CameraAudioState` — state models already track connection status, can be exposed via notification
- `appLog()` — structured logging, useful for debugging overnight service behavior
- `StorageService` — credential persistence (has TODO for flutter_secure_storage on Android)

### Established Patterns
- Riverpod `AsyncNotifier` for async state management
- Feature-first folder structure: `lib/features/{name}/screens|providers|models/`
- Defensive try/catch around all non-critical operations (level polling, property reads)
- `NativePlayer.setProperty()` for mpv configuration

### Integration Points
- `AudioPlayerNotifier.startMonitoring()` / `stopMonitoring()` — entry points the foreground service will call
- `MonitoringScreen` — currently triggers `startMonitoring` in initState, needs to coordinate with service lifecycle
- `app_router.dart` — route to monitoring screen on notification tap
- `pubspec.yaml` — needs flutter_foreground_task, audio_service, wakelock_plus dependencies added

</code_context>

<specifics>
## Specific Ideas

No specific requirements — open to standard approaches

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 03-android-background-operation*
*Context gathered: 2026-04-03*
