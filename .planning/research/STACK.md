# Technology Stack

**Project:** RTSP Audio Mixer (Baby Monitor)
**Researched:** 2026-04-01

## Recommended Stack

### Core Framework

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| Flutter | 3.27+ | Cross-platform app framework | Only viable option that covers Android (primary) + web (nice-to-have) with strong native interop for audio/foreground services. React Native's RTSP ecosystem is worse. Native Android-only kills the web goal. |
| Dart | 3.6+ | Application language | Comes with Flutter. Strong async/stream primitives fit the event-driven architecture (WebSocket listeners, audio streams). |

**Confidence:** HIGH -- Flutter is the right choice here. The RTSP and audio mixing requirements push toward native platform code, but Flutter's platform channel system handles this well, and media_kit (built on libmpv/FFmpeg) provides proven RTSP support.

### RTSP Audio Playback

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| media_kit | ^1.2.6 | RTSP stream connection and audio decoding | Built on libmpv (which uses FFmpeg internally). Supports RTSP natively, has explicit audio-only mode via `media_kit_libs_audio`, handles multiple simultaneous Player instances, and provides volume control per-player. This is the core of the app. |
| media_kit_libs_audio | ^1.0.7 | Audio-only native libraries (no video codecs) | Smaller binary, lower CPU/battery. Excludes video decoding entirely -- critical for overnight battery life. Do NOT mix with media_kit_libs_video. |

**Confidence:** HIGH -- media_kit is the most mature Flutter media library. It wraps libmpv which is battle-tested with RTSP streams. The audio-only library variant is exactly what this app needs.

**Architecture for two streams:** Create two separate `Player()` instances, each connecting to one camera's RTSP URL. Each player has independent `player.setVolume()` control. The OS audio mixer combines the outputs automatically -- no manual PCM mixing needed.

```dart
// Conceptual usage
final player1 = Player();
final player2 = Player();

await player1.open(Media('rtsps://192.168.1.1:7441/camera_id_1?enableSrtp'));
await player2.open(Media('rtsp://192.168.1.1:7447/camera_id_2'));

player1.setVolume(80.0); // 0-100
player2.setVolume(50.0);
```

**RTSP transport configuration:** Pass `--rtsp-transport=tcp` via mpv options for reliable LAN streaming (TCP avoids UDP packet loss issues on WiFi):

```dart
final player = Player(
  configuration: PlayerConfiguration(
    protocolWhitelist: ['rtp', 'rtsp', 'rtsps', 'tcp', 'udp', 'srtp'],
  ),
);
// Set mpv options before opening
(player.platform as NativePlayer).setProperty('rtsp-transport', 'tcp');
```

### Background Execution

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| flutter_foreground_task | ^9.2.2 | Android foreground service with persistent notification | Most actively maintained foreground service package. Supports two-way communication between service and UI isolate. Auto-resume on boot. Provides `mediaPlayback` foreground service type required by Android 14+. |
| audio_service | ^0.18.15 | Media session integration (lock screen, notification controls) | Integrates with Android's MediaSession for play/pause/volume on lock screen and notification area. Provides WAKE_LOCK. Complements flutter_foreground_task for the media playback use case. |

**Confidence:** MEDIUM-HIGH -- flutter_foreground_task is actively maintained (last release: hours ago). The combination with audio_service provides both the Android foreground service lifecycle AND media notification integration. Need to verify they don't conflict at runtime -- may only need one of the two.

**Critical Android detail:** Android 14+ requires declaring `android:foregroundServiceType="mediaPlayback"` in AndroidManifest.xml. Android 15 limits `dataSync` services to 6 hours/24 hours, but `mediaPlayback` has no such limit -- this is why the service type matters for overnight operation.

### Unifi Protect API Integration

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| dio | ^5.7+ | HTTP client for Protect API | Industry-standard Flutter HTTP client. Supports interceptors for auth token refresh, cookie management, and self-signed certificate handling (Unifi consoles use self-signed certs). |
| web_socket_channel | ^3.0+ | WebSocket client for real-time events | Dart-native WebSocket implementation. Connects to Protect's `wss://` updates endpoint for smart detection events (baby crying). |
| flutter_secure_storage | ^9.2+ | Credential storage | Stores Unifi Protect username/password using Android Keystore. Never store credentials in SharedPreferences. |

**Confidence:** MEDIUM -- There is no Dart/Flutter Unifi Protect API client library. The hjdhjd/unifi-protect npm package (TypeScript, v4.28.0) is the reference implementation but cannot be used directly in Dart. We must implement the Protect API client in Dart ourselves, using hjdhjd/unifi-protect as the authoritative reference for the reverse-engineered API.

**API endpoints we need to implement:**

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/auth/login` | POST | Authenticate, get cookie/token |
| `/proxy/protect/api/bootstrap` | GET | Discover cameras, NVR info, get lastUpdateId |
| `wss://.../proxy/protect/ws/updates?lastUpdateId=X` | WS | Real-time smart detection events |

**RTSP URL construction from bootstrap data:**
- RTSPS (encrypted): `rtsps://{nvr_ip}:7441/{camera_id}?enableSrtp`
- RTSP (unencrypted): `rtsp://{nvr_ip}:7447/{camera_id}`
- RTSP must be enabled per-camera in Unifi Protect settings (Advanced > RTSP)
- The bootstrap JSON contains camera objects with IDs and channel configurations

**WebSocket binary protocol:** The Protect updates WebSocket uses a custom binary protocol (not plain JSON). The hjdhjd/unifi-protect source code (specifically `protect-api-events.ts`) documents the packet structure. We need to port the binary deserialization to Dart. Smart detection events include `smartDetectTypes` which contains values like `"babyCrying"`.

### UI Framework

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| Flutter Material 3 | (built-in) | UI components | Default Flutter UI. Simple app with sliders, lists, and status indicators. No need for a custom design system. |

**Confidence:** HIGH -- The UI is minimal. Two volume sliders, a camera list, connection status, and audio level meters. Material 3 is more than sufficient.

### State Management

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| riverpod | ^2.6+ | Application state management | Handles async state well (stream connections, API responses). Provider-based architecture maps cleanly to this app's needs: auth state, camera list, player state, volume levels, connection status. |

**Confidence:** MEDIUM -- For an app this simple, even `setState` + `ChangeNotifier` could work. Riverpod is recommended because the app has genuinely async, interdependent state (auth -> cameras -> RTSP URLs -> players -> connection status). If the developer prefers simplicity, vanilla `ChangeNotifier` with `Provider` is fine too.

### Audio Level Metering

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| Custom implementation via media_kit | -- | Visual audio level meters | media_kit exposes audio data callbacks through libmpv. Use mpv's `af-metadata` or observe the `audio-pts` property. Alternatively, use a lightweight FFT on decoded PCM samples if available. |

**Confidence:** LOW -- Audio level metering from an RTSP stream in Flutter is not well-documented. Options: (1) Use libmpv's audio filter chain to get RMS levels, (2) Use a Dart FFT package on PCM data if we can access the raw audio buffer, (3) Skip metering in MVP and add later. This needs phase-specific research.

### Supporting Libraries

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| connectivity_plus | ^6.1+ | Network connectivity monitoring | Detect WiFi disconnection for auto-reconnect logic |
| flutter_local_notifications | ^18.0+ | Push notifications | Cry detection alerts when app is in background |
| wakelock_plus | ^1.2+ | Keep CPU awake | Prevent deep sleep during audio playback overnight |
| logging | ^1.3+ | Structured logging | Debug overnight connection issues after the fact |

## Alternatives Considered

| Category | Recommended | Alternative | Why Not |
|----------|-------------|-------------|---------|
| RTSP playback | media_kit | vlc_flutter / flutter_vlc_player | Less maintained, no audio-only variant, heavier binary size. media_kit's libmpv is more reliable for audio-only RTSP. |
| RTSP playback | media_kit | ffmpeg_kit_flutter_new | FFmpegKit is a command-line tool wrapper, not a player. Good for transcoding/processing but wrong abstraction for real-time audio playback. Would require piping FFmpeg output to a separate audio player. |
| RTSP playback | media_kit | Raw FFmpeg via platform channels | Too much native code to maintain. media_kit already wraps libmpv/FFmpeg properly. |
| Audio mixing | Two media_kit Players | Manual PCM mixing with flutter_pcm_sound | Unnecessary complexity. Two independent Player instances with per-player volume IS the mixer. The OS audio subsystem handles the actual sample mixing. |
| Foreground service | flutter_foreground_task | flutter_background_service | flutter_foreground_task is more actively maintained, better documented, and explicitly designed for foreground services rather than generic background execution. |
| State management | riverpod | bloc | BLoC is more boilerplate for an app this size. Riverpod's async providers map better to stream-based state. |
| HTTP client | dio | http | dio has interceptors (needed for auth token management) and better error handling. The built-in `http` package is too bare-bones for API client work with cookies and retries. |
| Protect API | Custom Dart client | Port hjdhjd/unifi-protect to Dart | Full port is overkill. We need ~5% of that library's functionality. Better to implement just the endpoints we need, referencing the TypeScript source. |

## Web Platform Limitations

**RTSP on web is not possible.** Browsers cannot connect to RTSP streams directly -- they lack the protocol support. This means:

- **Android:** Full functionality. media_kit uses libmpv natively for RTSP.
- **Web:** Cannot play RTSP streams. Would require a server-side proxy converting RTSP to HLS/WebSocket, adding 5-30 seconds of latency. This defeats the purpose for a baby monitor.

**Recommendation:** Build Android-first. The web target is a nice-to-have for the Protect API integration (camera selection, settings) but NOT for audio streaming. A web companion could show status/settings while audio plays on Android.

## Installation

```bash
# Core dependencies
flutter pub add media_kit media_kit_libs_audio
flutter pub add flutter_foreground_task
flutter pub add dio web_socket_channel flutter_secure_storage
flutter pub add flutter_riverpod riverpod_annotation
flutter pub add connectivity_plus flutter_local_notifications wakelock_plus logging

# Dev dependencies
flutter pub add -d riverpod_generator build_runner custom_lint riverpod_lint
```

## Key Version Constraints

| Constraint | Reason |
|------------|--------|
| Flutter >= 3.22.0 | Required by flutter_foreground_task 9.x |
| Dart >= 3.4.0 | Required by flutter_foreground_task 9.x |
| Kotlin >= 1.9.10 | Required by flutter_foreground_task 9.x |
| Gradle >= 8.6.0 | Required by flutter_foreground_task 9.x |
| Android minSdk >= 21 | Required by media_kit |
| Android targetSdk >= 34 | Required for foreground service type declarations |

## Sources

- [media_kit on pub.dev](https://pub.dev/packages/media_kit) -- v1.2.6, verified 2026-04-01
- [media_kit GitHub](https://github.com/media-kit/media-kit) -- RTSP support, multiple player instances, audio-only libs
- [flutter_foreground_task on pub.dev](https://pub.dev/packages/flutter_foreground_task) -- v9.2.2, verified 2026-04-01
- [hjdhjd/unifi-protect GitHub](https://github.com/hjdhjd/unifi-protect) -- v4.28.0, TypeScript reference implementation for Protect API
- [unifi-protect API docs](https://github.com/hjdhjd/unifi-protect/blob/main/docs/ProtectApi.md) -- Bootstrap, WebSocket, authentication
- [unifi-protect events source](https://github.com/hjdhjd/unifi-protect/blob/main/src/protect-api-events.ts) -- Binary WebSocket protocol reference
- [Unifi Protect RTSP community thread](https://community.ui.com/questions/Access-UniFi-Protect-camera-RTSP-stream/b1ba4c62-0764-4223-80d0-650768b0f87f) -- RTSPS port 7441, RTSP port 7447
- [Ubiquiti Protect Webhooks](https://help.ui.com/hc/en-us/articles/25478744592023-Send-UniFi-Protect-Alerts-to-Web-Services-using-Webhooks) -- Alternative to WebSocket for smart detection
- [audio_service on pub.dev](https://pub.dev/packages/audio_service) -- Background audio with media notification
- [flutter_pcm_sound GitHub](https://github.com/chipweinberger/flutter_pcm_sound/) -- Evaluated but not recommended (unnecessary for this architecture)
- [Browser RTSP limitations](https://www.red5.net/blog/how-to-use-rtsp-protocol-in-browsers/) -- Why web cannot play RTSP directly
