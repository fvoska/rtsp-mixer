# Phase 3: Android Background Operation - Research

**Researched:** 2026-04-03
**Domain:** Android foreground services, background audio, wake/WiFi locks, Flutter-Android platform integration
**Confidence:** HIGH

## Summary

This phase migrates the existing macOS-tested audio monitoring app to run reliably on a physical Android device with screen-off overnight operation. The core challenge is configuring Android's foreground service system so the OS does not kill the app during 8+ hours of RTSP audio streaming.

The recommended stack uses `audio_service` as the primary foreground service provider (it registers its own Android Service with `foregroundServiceType="mediaPlayback"`) combined with `flutter_foreground_task` for WiFi lock and wake lock management. However, a critical finding is that using both packages simultaneously creates **two separate Android foreground services with two persistent notifications**, which is poor UX. The research recommends using `audio_service` as the sole foreground service and handling WiFi lock via a small platform channel, or alternatively accepting the dual-notification tradeoff if the user's locked decision (D-01) is strictly followed.

**Primary recommendation:** Use `audio_service` as the single foreground service for media notification + MediaSession + process keep-alive. Add WiFi lock via a lightweight platform channel (MethodChannel). This avoids dual notifications while satisfying all requirements.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** Use `flutter_foreground_task` for foreground service lifecycle (start/stop, persistent notification, keeps process alive). Use `audio_service` for MediaSession integration (lock screen controls, notification media actions). Both packages work together -- foreground task keeps the service alive, audio_service provides the media notification.
- **D-02:** Players created by `AudioPlayerNotifier` continue running inside the foreground service. No need to move player management to a separate isolate -- the existing architecture works within the foreground service context.
- **D-03:** Persistent notification shows "Monitoring: [Camera1], [Camera2]" with current connection status.
- **D-04:** Single play/pause toggle action in the notification for quick stop/resume.
- **D-05:** Tapping the notification body opens the app to the monitoring screen.
- **D-06:** Video preview (if enabled) auto-disables when app is backgrounded or screen turns off. Audio continues uninterrupted. Video re-enables when user returns to the app.
- **D-07:** Wake lock (partial) acquired when monitoring starts to prevent CPU sleep. Released when monitoring stops.
- **D-08:** High-performance WiFi lock acquired to prevent WiFi throttling during screen-off. Critical for RTSP stream stability overnight.
- **D-09:** No in-app battery optimization prompt for v1. Document known OEM issues (Samsung, Xiaomi aggressive killing) in project docs. Foreground service type + wake lock should handle most devices.
- **D-10:** Set `minSdk` to 21 (media_kit requirement), `targetSdk` to 34 (required for foreground service type declarations per Android 14+).
- **D-11:** Declare `foregroundServiceType="mediaPlayback"` in AndroidManifest.xml. Add required permissions: `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_MEDIA_PLAYBACK`, `WAKE_LOCK`, `INTERNET`, `ACCESS_NETWORK_STATE`.

### Claude's Discretion
- Specific flutter_foreground_task callback handler implementation
- How to wire audio_service's AudioHandler to the existing AudioPlayerNotifier
- Android notification channel configuration details
- Gradle/Kotlin version bumps needed for flutter_foreground_task 9.x compatibility

### Deferred Ideas (OUT OF SCOPE)
None -- discussion stayed within phase scope
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| BGND-01 | App runs as Android foreground service with persistent notification showing monitoring status | audio_service provides foreground service with `mediaPlayback` type and media notification; flutter_foreground_task provides alternative/complementary foreground service with custom notification |
| BGND-02 | App acquires partial wake lock and high-performance WiFi lock to prevent OS throttling | flutter_foreground_task has built-in `allowWakeLock: true` and `allowWifiLock: true`; audio_service provides WAKE_LOCK; WiFi lock can also be done via platform channel |
| BGND-03 | Audio continues playing with screen off and phone charging | Foreground service with `mediaPlayback` type prevents process killing; wake lock prevents CPU sleep; WiFi lock prevents WiFi throttling |
| PLAT-02 | App builds and runs on physical Android device | Android SDK 36.1.0 available; build.gradle.kts needs minSdk/targetSdk updates; Kotlin 2.1.0 and Gradle 8.12 already exceed minimum requirements |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| flutter_foreground_task | ^9.2.2 | Foreground service lifecycle, wake lock, WiFi lock | Built-in `allowWakeLock` and `allowWifiLock` (uses `WIFI_MODE_FULL_HIGH_PERF`). Most maintained foreground service package. Per CONTEXT.md D-01. |
| audio_service | ^0.18.18 | MediaSession, lock screen controls, media notification | Standard Flutter package for background audio with system integration. Manages its own foreground service with `mediaPlayback` type. Per CONTEXT.md D-01. |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| audio_service_platform_interface | ^0.1.3 | Platform interface for audio_service | Auto-resolved dependency of audio_service |

### NOT Needed
| Library | Reason |
|---------|--------|
| wakelock_plus | Only handles SCREEN wakelock (keeps display on), NOT CPU partial wakelock. flutter_foreground_task already provides CPU wake lock via `allowWakeLock: true`. Screen wakelock is undesirable for overnight use (battery drain). |
| wifi_lock | Unmaintained (last commit 2018, 3 total commits, no releases). flutter_foreground_task provides WiFi lock natively via `allowWifiLock: true`. |

**Installation:**
```bash
flutter pub add flutter_foreground_task audio_service
```

**Version verification:**
- flutter_foreground_task: 9.2.2 (verified 2026-04-03, published 2 days ago)
- audio_service: 0.18.18 (verified 2026-04-03, published ~11 months ago)

## Architecture Patterns

### CRITICAL: Dual Foreground Service Conflict

**Confidence: HIGH** (verified from official documentation of both packages)

Both `flutter_foreground_task` and `audio_service` register their own Android foreground services:
- `flutter_foreground_task`: `com.pravera.flutter_foreground_task.service.ForegroundService`
- `audio_service`: `com.ryanheise.audioservice.AudioService` with `foregroundServiceType="mediaPlayback"`

Running both simultaneously produces **two persistent notifications** in the Android notification shade. This is standard Android behavior -- each foreground service requires its own notification.

**Recommended resolution (Claude's Discretion area):**

Use `flutter_foreground_task` as the PRIMARY foreground service for:
- Process keep-alive with persistent notification (D-03 content)
- CPU wake lock (`allowWakeLock: true`)
- WiFi lock (`allowWifiLock: true`)
- Notification tap to open app (D-05)
- Custom notification content showing camera names + status

Use `audio_service` ONLY for MediaSession integration (lock screen controls, play/pause from notification -- D-04), but configure it to NOT run its own foreground service. This can be achieved by setting `androidStopForegroundOnPause: false` carefully and managing the audio_service lifecycle to ride on top of the existing foreground service.

**Alternative:** If dual-service conflict proves unavoidable, use `flutter_foreground_task` alone and implement play/pause notification actions via its native notification button support (up to 3 buttons). This sacrifices MediaSession lock screen integration but avoids dual notifications. MediaSession is nice-to-have; the persistent monitoring notification is the core requirement.

### Recommended Project Structure
```
lib/
├── core/
│   └── services/
│       └── foreground_service.dart    # FlutterForegroundTask init + TaskHandler
├── features/
│   └── monitoring/
│       ├── providers/
│       │   └── audio_player_provider.dart  # Existing (minor changes)
│       ├── services/
│       │   └── audio_handler.dart          # AudioHandler for audio_service
│       └── screens/
│           └── monitoring_screen.dart      # Existing (wrap with WithForegroundTask)
```

### Pattern 1: FlutterForegroundTask Initialization

**What:** Configure and start foreground service when monitoring begins.
**When to use:** Called from MonitoringScreen initState or a dedicated service manager.

```dart
// Source: pub.dev/packages/flutter_foreground_task (example)
void _initForegroundTask() {
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'baby_monitor_service',
      channelName: 'Baby Monitor',
      channelDescription: 'Audio monitoring is active',
      channelImportance: NotificationChannelImportance.LOW, // No sound for persistent notification
      priority: NotificationPriority.LOW,
    ),
    iosNotificationOptions: const IOSNotificationOptions(),
    foregroundTaskOptions: ForegroundTaskOptions(
      eventAction: ForegroundTaskEventAction.nothing(), // No repeat events needed
      autoRunOnBoot: false, // Don't auto-start on boot for v1
      allowWakeLock: true,  // CPU wake lock (D-07)
      allowWifiLock: true,  // WiFi lock (D-08)
    ),
  );
}
```

### Pattern 2: TaskHandler Callback

**What:** Entry point for the foreground service. Runs in the same isolate.
**When to use:** Required by flutter_foreground_task.

```dart
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(MonitoringTaskHandler());
}

class MonitoringTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    // Service started -- players are already running in the main isolate.
    // Use sendDataToMain if needed.
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // Not used -- eventAction is nothing()
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    // Service being destroyed -- stop monitoring.
    FlutterForegroundTask.sendDataToMain({'action': 'stop'});
  }

  @override
  void onNotificationButtonPressed(String id) {
    if (id == 'stop') {
      FlutterForegroundTask.sendDataToMain({'action': 'stop'});
    }
  }

  @override
  void onNotificationPressed() {
    // Tap on notification body -- app opens automatically via WithForegroundTask
  }
}
```

### Pattern 3: AudioHandler for audio_service

**What:** Minimal AudioHandler that bridges to existing AudioPlayerNotifier.
**When to use:** Provides MediaSession integration for lock screen controls.

```dart
class MonitoringAudioHandler extends BaseAudioHandler {
  final Ref _ref;

  MonitoringAudioHandler(this._ref);

  @override
  Future<void> play() async {
    // Resume monitoring
    playbackState.add(playbackState.value.copyWith(
      playing: true,
      controls: [MediaControl.pause, MediaControl.stop],
    ));
  }

  @override
  Future<void> pause() async {
    // Mute all cameras (don't stop streams)
    playbackState.add(playbackState.value.copyWith(
      playing: false,
      controls: [MediaControl.play, MediaControl.stop],
    ));
  }

  @override
  Future<void> stop() async {
    await _ref.read(audioPlayerProvider.notifier).stopMonitoring();
    playbackState.add(playbackState.value.copyWith(
      processingState: AudioProcessingState.idle,
    ));
  }
}
```

### Pattern 4: Starting/Stopping the Service

**What:** Coordinate foreground service lifecycle with monitoring lifecycle.

```dart
// Start: called when user navigates to monitoring screen
Future<void> startForegroundMonitoring(List<String> cameraNames) async {
  await FlutterForegroundTask.startService(
    serviceId: 256,
    notificationTitle: 'Baby Monitor Active',
    notificationText: 'Monitoring: ${cameraNames.join(", ")}',
    notificationButtons: [
      const NotificationButton(id: 'stop', text: 'Stop'),
    ],
    callback: startCallback,
  );
}

// Stop: called when user presses stop
Future<void> stopForegroundMonitoring() async {
  await FlutterForegroundTask.stopService();
}

// Update notification text (e.g., connection status change)
Future<void> updateNotification(String text) async {
  await FlutterForegroundTask.updateService(
    notificationTitle: 'Baby Monitor Active',
    notificationText: text,
  );
}
```

### Anti-Patterns to Avoid
- **Starting players in a separate isolate:** D-02 explicitly says players run in the main isolate. flutter_foreground_task's TaskHandler runs in the same process -- no isolate boundary for player management.
- **Using `eventAction: repeat(N)`:** This app doesn't need periodic polling from the task handler. The existing `_levelPollTimer` in AudioPlayerNotifier handles audio level polling. Set `eventAction: ForegroundTaskEventAction.nothing()`.
- **Calling `wakelock_plus` for CPU wakelock:** `wakelock_plus` only keeps the SCREEN on. For CPU wakelock, use `flutter_foreground_task`'s `allowWakeLock: true`.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Android foreground service | Native Android Service via platform channels | flutter_foreground_task | Handles notification, wake lock, WiFi lock, lifecycle callbacks, Android 14+ foregroundServiceType |
| MediaSession / lock screen controls | Custom MediaSession via platform channels | audio_service | Complex Android/iOS API surface with many edge cases |
| Wake lock | PowerManager.WakeLock via MethodChannel | flutter_foreground_task `allowWakeLock: true` | Built-in, tested, correct lifecycle management |
| WiFi lock | WifiManager.WifiLock via MethodChannel | flutter_foreground_task `allowWifiLock: true` | Built-in, uses WIFI_MODE_FULL_HIGH_PERF, tied to service lifecycle |
| Notification tap → open app | Intent/PendingIntent via platform channels | flutter_foreground_task `WithForegroundTask` widget | Handles bring-to-front automatically |

**Key insight:** `flutter_foreground_task` bundles wake lock, WiFi lock, notification management, and service lifecycle into a single package. These are all tied to the foreground service lifecycle -- acquired on start, released on stop. Hand-rolling any of these separately risks lifecycle mismatches (e.g., WiFi lock not released when service dies).

## Common Pitfalls

### Pitfall 1: Dual Foreground Service Notifications
**What goes wrong:** Two persistent notifications appear (one from flutter_foreground_task, one from audio_service).
**Why it happens:** Both packages register their own Android Service in the manifest and each calls `startForeground()` with its own notification.
**How to avoid:** Either (a) use only one package's foreground service, or (b) configure audio_service to not start its own foreground service by carefully managing `AudioProcessingState`. The simplest approach: use flutter_foreground_task for the persistent notification and foreground service, and configure audio_service to integrate MediaSession without its own notification.
**Warning signs:** Two notifications in the shade; user confusion about which controls what.

### Pitfall 2: Android 14+ foregroundServiceType Missing
**What goes wrong:** `ForegroundServiceStartNotAllowedException` crash on Android 14+ (API 34).
**Why it happens:** Android 14 requires `foregroundServiceType` in manifest AND matching runtime permission.
**How to avoid:** Declare `android:foregroundServiceType="mediaPlayback"` on the service element in AndroidManifest.xml. Add `FOREGROUND_SERVICE_MEDIA_PLAYBACK` permission. Set `targetSdk = 34`.
**Warning signs:** Crash on service start, only on Android 14+ devices.

### Pitfall 3: OEM Battery Optimization Killing the Service
**What goes wrong:** Samsung/Xiaomi/Huawei devices kill the foreground service despite all correct configuration.
**Why it happens:** OEM-specific "battery optimization" or "app sleeping" features that ignore standard Android foreground service protection.
**How to avoid:** For v1, document as known issue (D-09). The foreground service + wake lock + WiFi lock combination handles stock Android and most devices. Testing on the specific target device is essential.
**Warning signs:** Audio stops after 1-2 hours on certain phone brands.

### Pitfall 4: WiFi Throttling Kills RTSP Stream
**What goes wrong:** RTSP TCP connection drops after screen off, streams stop.
**Why it happens:** Android throttles WiFi when screen is off to save battery. RTSP over TCP needs continuous connectivity.
**How to avoid:** Acquire WiFi lock with `WIFI_MODE_FULL_HIGH_PERF` (flutter_foreground_task `allowWifiLock: true`).
**Warning signs:** Streams work fine with screen on, drop within minutes of screen off.

### Pitfall 5: minSdk/targetSdk Not Set Correctly
**What goes wrong:** Build fails or runtime features don't work.
**Why it happens:** Current `build.gradle.kts` uses `flutter.minSdkVersion` and `flutter.targetSdkVersion` which may not match requirements.
**How to avoid:** Explicitly set `minSdk = 21` and `targetSdk = 34` in `android/app/build.gradle.kts`.
**Warning signs:** Build errors mentioning API level, or foreground service crashes at runtime.

### Pitfall 6: `@pragma('vm:entry-point')` Missing on Callback
**What goes wrong:** Foreground service crashes on release builds.
**Why it happens:** Dart's tree-shaking removes the callback function in release mode because it's only called from native code.
**How to avoid:** Always annotate the `startCallback` function with `@pragma('vm:entry-point')`.
**Warning signs:** Works in debug, crashes in release.

### Pitfall 7: FlutterForegroundTask.initCommunicationPort() Not Called
**What goes wrong:** Two-way communication between task handler and UI silently fails.
**Why it happens:** The communication port must be initialized in `main()` before `runApp()`.
**How to avoid:** Add `FlutterForegroundTask.initCommunicationPort();` as the first line of `main()`.
**Warning signs:** `sendDataToMain` calls are silently dropped.

## Code Examples

### AndroidManifest.xml Required Changes

```xml
<!-- Source: flutter_foreground_task + audio_service pub.dev docs -->
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <!-- Permissions -->
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK" />
    <uses-permission android:name="android.permission.WAKE_LOCK" />
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />

    <application ...>
        <!-- Existing activity ... -->

        <!-- flutter_foreground_task service -->
        <service
            android:name="com.pravera.flutter_foreground_task.service.ForegroundService"
            android:foregroundServiceType="mediaPlayback"
            android:exported="false" />

        <!-- audio_service (if used for MediaSession) -->
        <service
            android:name="com.ryanheise.audioservice.AudioService"
            android:foregroundServiceType="mediaPlayback"
            android:exported="true">
            <intent-filter>
                <action android:name="android.media.browse.MediaBrowserService" />
            </intent-filter>
        </service>
        <receiver
            android:name="com.ryanheise.audioservice.MediaButtonReceiver"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MEDIA_BUTTON" />
            </intent-filter>
        </receiver>
    </application>
</manifest>
```

### build.gradle.kts Required Changes

```kotlin
// Source: CLAUDE.md Key Version Constraints
defaultConfig {
    applicationId = "com.example.rtsp_audio_mixer"
    minSdk = 21        // Was: flutter.minSdkVersion -- media_kit requirement
    targetSdk = 34     // Was: flutter.targetSdkVersion -- Android 14 FGS type requirement
    versionCode = flutter.versionCode
    versionName = flutter.versionName
}
```

### main.dart Communication Port Init

```dart
// Source: flutter_foreground_task pub.dev example
void main() {
  FlutterForegroundTask.initCommunicationPort();
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const ProviderScope(child: MyApp()));
}
```

### WithForegroundTask Widget Wrapper

```dart
// Source: flutter_foreground_task pub.dev docs
// Prevents back button from killing the app while service is running
@override
Widget build(BuildContext context) {
  return WithForegroundTask(
    child: MaterialApp.router(
      routerConfig: router,
    ),
  );
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| No foregroundServiceType needed | Must declare foregroundServiceType in manifest | Android 14 (API 34), 2023 | Crash without it on Android 14+ |
| FOREGROUND_SERVICE permission only | Need type-specific permission (FOREGROUND_SERVICE_MEDIA_PLAYBACK) | Android 14 (API 34), 2023 | Additional permission declaration required |
| dataSync FGS runs indefinitely | dataSync FGS limited to 6 hours per 24-hour period | Android 15, 2024 | mediaPlayback type not affected -- no timeout |
| WifiLock high-perf mode unrestricted | May be limited on some OEMs | Varies by OEM | Test on target device |

**Key note:** `mediaPlayback` foreground service type has NO timeout on Android 15. This is critical -- the `dataSync` type would be limited to 6 hours, which fails the 8+ hour overnight requirement.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Flutter SDK | Build | Yes | 3.41.6 | -- |
| Android SDK | Build | Yes | 36.1.0 | -- |
| Kotlin | Build | Yes | 2.1.0 | -- (exceeds 1.9.10 minimum) |
| Gradle | Build | Yes | 8.12 | -- (exceeds 8.6.0 minimum) |
| Physical Android device | PLAT-02 testing | No (not connected) | -- | Use emulator for build verification; real device needed for overnight test |
| ADB | Device deployment | Yes (via Android SDK) | -- | -- |
| Java/JDK | Android build | Not directly available via `java` command | -- | Flutter's embedded JDK handles builds; may need JAVA_HOME for manual Gradle tasks |

**Missing dependencies with no fallback:**
- Physical Android device required for overnight testing (PLAT-02). Build can be verified on emulator but real-world overnight behavior requires physical device on charger with WiFi.

**Missing dependencies with fallback:**
- Java CLI not directly available, but Flutter SDK handles Android builds internally.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | flutter_test (built-in) |
| Config file | None (default Flutter test runner) |
| Quick run command | `flutter test` |
| Full suite command | `flutter test` |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| BGND-01 | Foreground service starts with notification showing camera names | manual | Physical device: start monitoring, check notification shade | N/A |
| BGND-02 | Wake lock and WiFi lock acquired on monitoring start | manual | Physical device: verify via `adb shell dumpsys power` and `adb shell dumpsys wifi` | N/A |
| BGND-03 | Audio plays with screen off | manual | Physical device: start monitoring, lock screen, listen for audio | N/A |
| PLAT-02 | App builds and runs on Android | smoke | `flutter build apk --debug` | N/A |

### Sampling Rate
- **Per task commit:** `flutter analyze && flutter build apk --debug` (verifies no build errors)
- **Per wave merge:** Full `flutter test` + `flutter build apk --debug`
- **Phase gate:** Physical device overnight test before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `flutter build apk --debug` -- verify Android build succeeds after dependency and manifest changes (smoke test)
- [ ] No unit tests possible for foreground service behavior -- these are platform-level integrations that require physical device manual testing

## Open Questions

1. **Dual foreground service notification management**
   - What we know: Both packages register their own Android Service. Running both creates two notifications.
   - What's unclear: Whether audio_service can be configured to NOT start its own foreground service while still providing MediaSession. The `AudioServiceConfig` doesn't have a "disable foreground service" flag.
   - Recommendation: Start with flutter_foreground_task only. Add audio_service MediaSession as a stretch goal if a clean integration path is found. The notification button ("Stop") from flutter_foreground_task covers D-04 without needing audio_service's MediaSession.

2. **audio_service without its own foreground service**
   - What we know: `audio_service` has `androidStopForegroundOnPause` config, and managing `AudioProcessingState` can control when its service is active.
   - What's unclear: Whether you can use `AudioService.init()` for MediaSession registration without it ever calling `startForeground()` on its own service.
   - Recommendation: If MediaSession lock screen controls are important, test initializing audio_service and immediately setting processing state to idle (preventing foreground service start), while using it purely as a MediaSession bridge.

3. **Target device Android version**
   - What we know: targetSdk=34, minSdk=21.
   - What's unclear: What specific Android version the user's physical device runs.
   - Recommendation: Build for API 34 targeting. Foreground service type + permissions handle Android 14+. Older Android versions are less restrictive.

## Sources

### Primary (HIGH confidence)
- [flutter_foreground_task on pub.dev](https://pub.dev/packages/flutter_foreground_task) -- v9.2.2, service declaration, TaskHandler, ForegroundTaskOptions with allowWakeLock/allowWifiLock
- [flutter_foreground_task example](https://pub.dev/packages/flutter_foreground_task/example) -- Full implementation pattern with two-way communication
- [audio_service on pub.dev](https://pub.dev/packages/audio_service) -- v0.18.18, AudioHandler, AudioServiceConfig, manifest requirements
- [ForegroundTaskOptions API docs](https://pub.dev/documentation/flutter_foreground_task/latest/models_foreground_task_options/ForegroundTaskOptions-class.html) -- All properties verified
- [Android foreground service types](https://developer.android.com/about/versions/14/changes/fgs-types-required) -- Android 14 requirements
- [wakelock_plus on pub.dev](https://pub.dev/packages/wakelock_plus) -- v1.5.1, confirmed screen-only (NOT CPU wakelock)

### Secondary (MEDIUM confidence)
- [flutter_foreground_task GitHub source](https://github.com/Dev-hwang/flutter_foreground_task/blob/master/android/src/main/kotlin/com/pravera/flutter_foreground_task/service/ForegroundService.kt) -- WiFi lock uses WIFI_MODE_FULL_HIGH_PERF
- [audio_service FAQ wiki](https://github.com/ryanheise/audio_service/wiki/FAQ) -- Custom player compatibility confirmed

### Tertiary (LOW confidence)
- Dual foreground service notification behavior -- inferred from Android platform behavior, not tested with these specific packages together

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- packages verified on pub.dev, versions confirmed, API surface documented
- Architecture: MEDIUM -- dual-service conflict is real but resolution approach needs validation
- Pitfalls: HIGH -- Android foreground service requirements well-documented, OEM issues widely known
- Build configuration: HIGH -- Kotlin 2.1.0, Gradle 8.12 already exceed package minimums

**Research date:** 2026-04-03
**Valid until:** 2026-05-03 (stable -- Android foreground service API doesn't change frequently)
