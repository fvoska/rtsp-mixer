# Architecture Patterns

**Domain:** RTSP audio baby monitor with background service  
**Researched:** 2026-04-01

## Recommended Architecture

The app has five major subsystems that communicate through well-defined boundaries. The architecture is driven by one overriding constraint: **the audio pipeline must survive 8+ hours in a foreground service with the screen off**. This means the entire audio path (RTSP connection, decoding, mixing, output) lives in the service layer, not the UI layer.

```
+-----------------------------------------------------+
|                    Flutter UI Layer                   |
|  (Camera list, volume sliders, level meters, config) |
+---------------------------+--------------------------+
                            |
                   State management
                   (Riverpod providers)
                            |
+---------------------------+--------------------------+
|              Foreground Service Layer                 |
|  (Owns all long-lived resources, survives screen-off)|
+------+----------+----------+----------+--------------+
       |          |          |          |
  +----+---+ +---+----+ +---+----+ +---+--------+
  | RTSP   | | Audio  | | Protect| | Health     |
  | Stream | | Pipe-  | | API    | | Monitor    |
  | Mgr    | | line   | | Client | | (watchdog) |
  +--------+ +--------+ +--------+ +------------+
```

### Component Boundaries

| Component | Responsibility | Communicates With |
|-----------|---------------|-------------------|
| **Flutter UI** | Display camera list, volume sliders, audio level meters, connection status, settings | Foreground Service (via state management) |
| **Foreground Service** | Host all long-lived resources, manage Android lifecycle, show persistent notification | All subsystems (owns them) |
| **RTSP Stream Manager** | Connect to RTSP URLs, handle reconnection, extract audio track | Audio Pipeline (feeds decoded audio), Health Monitor (reports status) |
| **Audio Pipeline** | Decode audio, apply per-camera volume, mix two streams, compute levels, output to speaker | RTSP Stream Manager (receives audio), UI (publishes level data) |
| **Protect API Client** | Authenticate, discover cameras, subscribe to smart detection events | UI (camera list), RTSP Stream Manager (provides RTSP URLs), Foreground Service (cry detection triggers) |
| **Health Monitor** | Watchdog for stream health, trigger reconnection, track connection stats | RTSP Stream Manager (monitors), Foreground Service (updates notification) |

## Detailed Component Design

### 1. RTSP Stream Manager

**Technology:** `media_kit` (libmpv via dart:ffi)

**Why media_kit over flutter_vlc_player:**
- 80%+ implementation in Dart FFI, more predictable cross-platform behavior
- Supports audio-only mode without video rendering overhead (just use core `media_kit` package, skip `media_kit_video`)
- libmpv handles RTSP natively with configurable transport (TCP/UDP)
- Multiple simultaneous Player instances supported (resolved in Dart SDK 3.1.0+)
- Active maintenance, good issue response times

**Confidence:** MEDIUM -- media_kit with RTSP audio-only has not been explicitly documented for this use case, but the components (RTSP support + audio-only mode + multiple instances) are all individually confirmed.

**Key responsibilities:**
- Create two `Player` instances, one per camera
- Configure for audio-only: `--vid=no` (libmpv option to skip video decoding entirely)
- Configure for low-latency: reduce buffer sizes since we need real-time monitoring
- Expose stream status (connected/buffering/error/disconnected)
- Delegate reconnection logic to Health Monitor

**RTSP URL format for Unifi Protect:**
```
rtsps://<protect-host>:7441/<camera-stream-id>
  -- or --
rtsp://<protect-host>:7447/<camera-stream-id>
```

Stream IDs come from the Protect API bootstrap response. Prefer RTSPS (port 7441) when certificate validation can be configured.

**Per-player configuration (libmpv options):**
```
vid=no                    # No video decoding
demuxer-lavf-o=rtsp_transport=tcp  # TCP transport for reliability on LAN
cache=no                  # Minimize latency
demuxer-readahead-secs=1  # Small buffer for real-time
```

### 2. Audio Pipeline

**Architecture decision: Let media_kit/libmpv handle mixing at the OS level.**

Rather than extracting raw PCM from both streams and mixing in Dart, the simpler and more reliable approach is:

1. Run two `media_kit` Player instances simultaneously
2. Both output to the default audio device (Android AudioTrack)
3. Android's audio system handles the actual mixing of two audio outputs
4. Per-camera volume control via `Player.setVolume(0.0 - 1.0)`

**Why not PCM-level mixing in Dart:**
- Adds complexity: extract raw audio, align timestamps, mix samples, output via raw PCM player
- Battery cost: Dart isolate doing PCM math all night
- Fragile: buffer synchronization, sample rate conversion, underrun handling
- No benefit: Android already mixes multiple audio streams at the HAL level

**Audio level metering:**
This is the one area where we need raw audio data. Two approaches:

- **Option A (recommended):** Use media_kit's audio callback/filter functionality if available to tap into the decoded PCM stream for level computation, without actually replacing the output path.
- **Option B (fallback):** Use Android's `Visualizer` API via a platform channel. The Visualizer attaches to an audio session and provides waveform/FFT data without intercepting the audio path. This is the standard Android approach for level meters.

**Level meter data flow:**
```
media_kit Player -> Android AudioTrack -> Visualizer API (platform channel)
    -> RMS computation (native side, lightweight)
    -> Stream<double> published to Dart
    -> UI updates at ~10-15 fps (throttled)
```

**Confidence:** HIGH for dual-player approach. MEDIUM for level metering (Visualizer API is well-documented on Android but needs platform channel implementation).

### 3. Unifi Protect API Client

**Architecture: Pure Dart HTTP + WebSocket client.** No third-party Protect library exists for Dart. Port the patterns from `hjdhjd/unifi-protect` (TypeScript reference implementation).

**Authentication flow:**
```
1. POST https://<host>/api/auth/login
   Body: { username, password }
   Response: Set-Cookie header with auth token + X-CSRF-Token

2. Store cookie + CSRF token for subsequent requests

3. GET https://<host>/proxy/protect/api/bootstrap
   Returns: Full system state (NVR info, all cameras, users, settings)

4. Extract from bootstrap:
   - Camera list (id, name, type, connection state)
   - RTSP stream channel info (quality levels, stream IDs)
   - lastUpdateId (for WebSocket subscription)
```

**Camera discovery data model:**
```dart
class ProtectCamera {
  final String id;
  final String name;
  final String type;         // e.g., "UVC G4 Dome"
  final bool isConnected;
  final List<StreamChannel> channels;  // Low/Medium/High quality
  final String? lastSmartDetectType;
}

class StreamChannel {
  final int id;
  final String rtspAlias;    // Used to construct RTSP URL
  final int width;
  final int height;
  final bool isRtspEnabled;
}
```

**Smart detection event subscription:**
```
WebSocket: wss://<host>/proxy/protect/ws/updates?lastUpdateId=<id>

Binary protocol:
  - Header: action type, model key (e.g., "event"), device ID
  - Payload: JSON with event details

Filter for: smartDetectTypes containing "babyCrying"
```

**Event flow for cry detection:**
```
Protect WebSocket -> parse binary frame -> check modelKey == "event"
  -> check smartDetectTypes includes "babyCrying"
  -> check camera ID matches user's selected cameras
  -> if camera in "cry-triggered" mode:
      -> start RTSP stream for that camera
      -> fire local notification
```

**Auth persistence:** Store credentials in `flutter_secure_storage`. On app launch, attempt re-authentication silently. If token expired, re-login with stored credentials.

**Confidence:** MEDIUM -- The Protect API is undocumented by Ubiquiti. The `hjdhjd/unifi-protect` TypeScript library is the best reference, but API changes with firmware updates are a risk.

### 4. Android Foreground Service

**Technology:** `flutter_foreground_task` package

**Why `flutter_foreground_task` over `audio_service`:**
- `audio_service` is designed for media player apps (play/pause/skip controls, media session integration). Our app is a monitor, not a media player.
- `flutter_foreground_task` provides a generic foreground service with persistent notification, without imposing media player semantics.
- More control over notification content (show "Listening to Room 1 + Room 2" instead of media controls).
- Supports `android:foregroundServiceType="mediaPlayback"` required by Android 14+.

**Service lifecycle:**
```
App Launch
  -> Authenticate with Protect API
  -> User selects cameras
  -> User taps "Start Listening"
  -> Start foreground service
  -> Initialize media_kit Players inside service
  -> Connect RTSP streams
  -> Show persistent notification: "Monitoring: [Camera 1], [Camera 2]"
  -> Start WebSocket for smart detection events
  -> App goes to background / screen off
  -> Service keeps running (foreground service protection)
  -> Health monitor watches for stream drops
  -> On stream drop: reconnect with exponential backoff
  -> User returns to app: UI reconnects to service state
  -> User taps "Stop" or kills app: service stops, streams close
```

**Android Manifest requirements:**
```xml
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK" />
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" /> <!-- Android 13+ -->

<service
    android:name="com.pravera.flutter_foreground_task.service.ForegroundService"
    android:foregroundServiceType="mediaPlayback"
    android:stopWithTask="false" />  <!-- keep running if task swiped -->
```

**Note on Android 15 dataSync timeout:** Does NOT apply to `mediaPlayback` foreground service type. The 6-hour limit is only for `dataSync` type services. `mediaPlayback` can run indefinitely, which is exactly what we need.

**Confidence:** HIGH -- `flutter_foreground_task` with `mediaPlayback` type is well-documented and widely used for this exact pattern.

### 5. State Management

**Technology:** Riverpod (with code generation)

**State architecture:**
```
+------------------+     +-------------------+     +------------------+
| Auth State       |     | Camera State      |     | Streaming State  |
| - credentials    |---->| - discovered list |---->| - player status  |
| - isLoggedIn     |     | - selected pair   |     | - volume levels  |
| - protectHost    |     | - per-cam mode    |     | - audio levels   |
|                  |     |   (continuous/    |     | - connection     |
|                  |     |    cry/off)       |     |   health         |
+------------------+     +-------------------+     +------------------+
         |                        |                         |
         v                        v                         v
   SharedPrefs /           Riverpod state            Service -> UI
   SecureStorage           (in-memory)               stream bridge
```

**Key providers:**
```dart
// Auth
@riverpod
class AuthNotifier extends _$AuthNotifier {
  // Login, logout, token refresh, credential persistence
}

// Camera discovery and selection
@riverpod  
class CameraListNotifier extends _$CameraListNotifier {
  // Fetch from bootstrap, user selection, mode per camera
}

// Streaming state (bridges foreground service -> UI)
@riverpod
Stream<StreamingState> streamingState(ref) {
  // Listens to foreground service state updates
  // Publishes connection status, audio levels, errors
}
```

**Service-to-UI communication:**
The foreground service runs in the same Dart isolate (flutter_foreground_task design), so state can be shared via Riverpod providers directly. No IPC or message passing needed. The service task handler has access to the same provider container.

**Confidence:** HIGH -- Standard Riverpod architecture, well-understood patterns.

### 6. Health Monitor (Watchdog)

**Purpose:** Ensure streams stay alive overnight. This is the most critical reliability component.

**Monitoring strategy:**
```
Every 30 seconds:
  - Check media_kit Player state for each active stream
  - If state == error or idle (unexpectedly):
    -> Increment failure counter
    -> Attempt reconnect with exponential backoff:
       1st: immediate retry
       2nd: 5 second delay
       3rd: 15 second delay
       4th+: 30 second delay, max 5 minutes
    -> After 10 consecutive failures:
       -> Fire high-priority notification: "Stream lost for [Camera Name]"
       -> Keep retrying at 5-minute intervals

  - Check WebSocket connection for smart detection events
  - If WebSocket disconnected:
    -> Re-authenticate (token may have expired)
    -> Re-establish WebSocket

  - Check WiFi connectivity
  - If WiFi lost:
    -> Pause reconnection attempts
    -> Resume when WiFi returns (use connectivity_plus)
```

**Notification escalation:**
- Normal operation: Low-priority persistent notification ("Monitoring: Room 1, Room 2")
- Stream reconnecting: Update notification ("Reconnecting to Room 1...")
- Stream lost > 2 minutes: High-priority notification with sound
- All streams lost: Critical notification

**Confidence:** HIGH -- These are standard reliability patterns. Implementation is straightforward.

## Data Flow

### Happy Path: Continuous Listening
```
1. User authenticates -> Protect API returns bootstrap
2. User selects 2 cameras -> RTSP URLs extracted from bootstrap
3. User taps "Start" -> Foreground service starts
4. Service creates 2 media_kit Players
5. Players connect to RTSP streams (audio-only, no video)
6. Android mixes both audio outputs to speaker
7. Visualizer API taps audio sessions -> level data -> UI meters
8. Volume sliders -> Player.setVolume() -> immediate effect
9. WebSocket monitors smart detection events in background
10. Health monitor polls stream health every 30s
11. Screen off -> service continues -> audio plays through speaker
```

### Cry-Triggered Mode
```
1. Camera 2 set to "cry-triggered" mode
2. RTSP stream for Camera 2 is NOT started
3. WebSocket receives smart detection event: babyCrying on Camera 2
4. Service starts RTSP stream for Camera 2
5. Service fires local notification: "Crying detected in Room 2"
6. Audio begins playing (mixed with Camera 1 if active)
7. After N minutes of no cry events: optionally stop Camera 2 stream
```

### Reconnection Flow
```
1. WiFi blip -> RTSP stream drops
2. media_kit Player reports error state
3. Health monitor detects within 30s
4. Immediate reconnect attempt
5. If fail: exponential backoff (5s, 15s, 30s, ...)
6. If WiFi still down: pause, wait for connectivity
7. WiFi returns -> immediate reconnect
8. Success -> update notification, reset failure counter
9. 10+ failures -> escalate notification to user
```

## Patterns to Follow

### Pattern 1: Service-Owned Resources
**What:** All long-lived resources (Players, WebSocket, HTTP client) are created and owned by the foreground service task handler, not by Flutter widgets.  
**When:** Always. This is non-negotiable for overnight reliability.  
**Why:** Widgets are destroyed when the screen turns off or the app goes to background. The service persists.

### Pattern 2: Reactive State Bridge
**What:** Service publishes state changes via Riverpod. UI subscribes reactively. No polling from UI side.  
**When:** Any time UI needs to reflect service state (levels, connection status, errors).  
**Example:**
```dart
// In service task handler
ref.read(streamingStateProvider.notifier).updateLevels(
  camera1Level: 0.42,
  camera2Level: 0.15,
);

// In UI widget
final state = ref.watch(streamingStateProvider);
AudioLevelMeter(level: state.camera1Level)
```

### Pattern 3: Graceful Degradation
**What:** If one stream fails, keep the other running. If WebSocket drops, keep RTSP streams. If auth expires during operation, attempt silent re-auth.  
**When:** Any error condition.  
**Why:** Parent is asleep. Partial monitoring is better than total failure.

### Pattern 4: Thin UI, Fat Service
**What:** UI is a dumb display layer. All logic (reconnection, event processing, volume mixing) lives in the service layer.  
**When:** Any feature that involves audio or network.  
**Why:** UI lifecycle is unreliable. Service lifecycle is controlled.

## Anti-Patterns to Avoid

### Anti-Pattern 1: Video Decoding "Just In Case"
**What:** Including media_kit_video or not disabling video track.  
**Why bad:** Video decoding consumes 10-50x more CPU and battery than audio-only. Over 8 hours, this is the difference between 20% battery drain and a dead phone.  
**Instead:** Explicitly set `vid=no` on every Player instance. Never include the video rendering package.

### Anti-Pattern 2: PCM-Level Mixing in Dart
**What:** Extracting raw PCM from both streams, mixing samples in a Dart isolate, outputting through a raw audio player.  
**Why bad:** Complex, battery-hungry, fragile (buffer sync issues), and unnecessary -- Android already mixes multiple audio outputs at the HAL.  
**Instead:** Two Player instances outputting simultaneously. Let the OS mix.

### Anti-Pattern 3: Polling Protect API for Events
**What:** Periodically hitting the Protect REST API to check for new smart detection events.  
**Why bad:** Latency (cry already happened minutes ago), battery drain, unnecessary network traffic.  
**Instead:** WebSocket subscription for real-time push events.

### Anti-Pattern 4: UI-Owned Network Connections
**What:** Creating RTSP connections or WebSocket in widget state.  
**Why bad:** Connections die when widget is disposed (screen off, app backgrounded, navigation).  
**Instead:** All connections owned by foreground service.

## Cross-Platform Considerations

### Android (Primary)
- Foreground service with `mediaPlayback` type -- well-supported, indefinite runtime
- media_kit uses libmpv native libraries -- bundled via `media_kit_libs_android_audio`
- Visualizer API for level metering -- native platform channel
- `flutter_secure_storage` uses Android Keystore

### Web (Nice-to-Have, Deferred)
- No foreground service concept -- browser tab must stay open
- media_kit does NOT support web -- would need alternative (HLS.js? direct WebSocket streaming?)
- RTSP not natively supported in browsers -- would need a proxy/transcoder
- WebSocket to Protect API works directly from browser (same-origin/CORS considerations)
- Level metering via Web Audio API AnalyserNode

**Recommendation:** Build Android-first. Web support requires a fundamentally different audio transport layer (RTSP -> WebSocket/HLS proxy). Do not try to abstract over both from day one. If web is pursued later, it should be a separate audio backend behind a shared interface.

## Build Order (Dependencies)

The build order is driven by what can be tested independently:

```
Phase 1: Protect API Client (standalone, testable with curl/Postman first)
   |-- Auth flow
   |-- Bootstrap parsing
   |-- Camera discovery
   |
Phase 2: Single RTSP Audio Stream (proves core feasibility)
   |-- media_kit setup
   |-- Connect to one camera
   |-- Audio-only playback
   |-- Volume control
   |
Phase 3: Foreground Service (makes single stream survive background)
   |-- flutter_foreground_task setup
   |-- Move Player into service
   |-- Persistent notification
   |-- Screen-off survival test
   |
Phase 4: Dual Streams + Mixing (complete audio experience)
   |-- Second Player instance
   |-- Simultaneous playback
   |-- Per-camera volume
   |-- Level metering (Visualizer API)
   |
Phase 5: Smart Detection + Cry Mode (full feature set)
   |-- WebSocket event subscription
   |-- Cry event parsing
   |-- Cry-triggered stream start
   |-- Local notifications
   |
Phase 6: Reliability Hardening (overnight survival)
   |-- Health monitor / watchdog
   |-- Reconnection with backoff
   |-- WiFi state awareness
   |-- Notification escalation
   |-- 8-hour soak test
```

**Rationale:** Each phase produces a testable increment. Phase 1-2 validates the hardest unknowns first (can we talk to Protect? can media_kit do RTSP audio-only?). Phase 3 is the critical Android-specific work. Phases 4-6 layer features on a proven foundation.

## Scalability Considerations

Not a scalability concern in the traditional sense (this is a single-user app on LAN), but relevant for resource constraints:

| Concern | Current (2 cameras) | If Extended to 4 cameras |
|---------|---------------------|--------------------------|
| CPU | Minimal (audio decode only) | Still minimal, 4 audio streams negligible |
| Battery | Primary concern -- test overnight drain | Slightly more, but still audio-only |
| Memory | ~2 libmpv instances + buffers (~30MB) | ~60MB, still fine |
| Network | ~128kbps per stream (AAC audio) | ~512kbps total, trivial on LAN |

## Sources

- [media_kit GitHub](https://github.com/media-kit/media-kit) -- RTSP audio playback via libmpv
- [flutter_foreground_task](https://pub.dev/packages/flutter_foreground_task) -- Android foreground service
- [audio_service](https://pub.dev/packages/audio_service) -- Considered but rejected (media player semantics)
- [hjdhjd/unifi-protect](https://github.com/hjdhjd/unifi-protect) -- Reference Protect API implementation
- [Protect API docs](https://github.com/hjdhjd/unifi-protect/blob/main/docs/ProtectApi.md) -- Auth, bootstrap, WebSocket protocol
- [flutter_vlc_player](https://pub.dev/packages/flutter_vlc_player) -- Considered but rejected (less Dart-native than media_kit)
- [Unifi Community - RTSP](https://community.ui.com/questions/How-does-RTSP-work-on-Protect/448bd517-7991-4d45-982c-33eff0d22184) -- RTSP port info
- [Android foreground service types](https://developer.android.com/about/versions/14/changes/fgs-types-required) -- Android 14+ requirements
- [mp_audio_stream](https://pub.dev/packages/mp_audio_stream) -- Raw PCM streaming (considered, rejected for complexity)
- [flutter_pcm_sound](https://github.com/chipweinberger/flutter_pcm_sound/) -- Raw PCM output (considered, rejected)
