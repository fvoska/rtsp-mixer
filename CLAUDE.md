<!-- GSD:project-start source:PROJECT.md -->
## Project

**RTSP Audio Mixer**

A baby monitor app that connects to Unifi Protect cameras, extracts audio-only from RTSP streams, and lets a parent listen to two rooms simultaneously with per-camera volume mixing. Designed to run reliably overnight on Android with the screen off — something the Unifi app and VLC can't do.

**Core Value:** Reliable overnight audio from two baby cameras that never silently dies — the parent must be able to trust it's still listening when they fall asleep.

### Constraints

- **Platform**: Android primary, web nice-to-have — Flutter is the candidate framework
- **Network**: Same LAN only — no need for cloud relay or remote tunneling
- **Audio only by default**: Video decoding disabled at runtime (`vid=no`). Optional video preview toggle available but auto-suspends when app is backgrounded/screen off.
- **Reliability**: Must survive 8+ hours unattended — auto-reconnect is non-negotiable
- **Background**: Android must not kill the app — foreground service with persistent notification
<!-- GSD:project-end -->

<!-- GSD:stack-start source:research/STACK.md -->
## Technology Stack

## Recommended Stack
### Core Framework
| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| Flutter | 3.27+ | Cross-platform app framework | Only viable option that covers Android (primary) + web (nice-to-have) with strong native interop for audio/foreground services. React Native's RTSP ecosystem is worse. Native Android-only kills the web goal. |
| Dart | 3.6+ | Application language | Comes with Flutter. Strong async/stream primitives fit the event-driven architecture (WebSocket listeners, audio streams). |
### RTSP Audio Playback
| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| media_kit | ^1.2.6 | RTSP stream connection and audio decoding | Built on libmpv (which uses FFmpeg internally). Supports RTSP natively, handles multiple simultaneous Player instances, and provides volume control per-player. This is the core of the app. |
| media_kit_video | ^1.2.6 | Video rendering for optional preview | Provides `Video` widget and `VideoController`. Used for optional video preview toggle — off by default, video disabled via `vid=no` mpv property. |
| media_kit_libs_video | ^1.0.6 | Full native libraries (FFmpeg with RTSP demuxer) | **Must use video libs, not audio-only.** The `media_kit_libs_audio` build strips the RTSP/RTSPS demuxer (`Unknown lavf format rtsp` error). The video libs include all protocol demuxers. Video decoding is disabled at runtime via `vid=no` to save CPU. |
### Background Execution
| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| flutter_foreground_task | ^9.2.2 | Android foreground service with persistent notification | Most actively maintained foreground service package. Supports two-way communication between service and UI isolate. Auto-resume on boot. Provides `mediaPlayback` foreground service type required by Android 14+. |
| audio_service | ^0.18.15 | Media session integration (lock screen, notification controls) | Integrates with Android's MediaSession for play/pause/volume on lock screen and notification area. Provides WAKE_LOCK. Complements flutter_foreground_task for the media playback use case. |
### Unifi Protect API Integration
| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| dio | ^5.7+ | HTTP client for Protect API | Industry-standard Flutter HTTP client. Supports interceptors for auth token refresh, cookie management, and self-signed certificate handling (Unifi consoles use self-signed certs). |
| web_socket_channel | ^3.0+ | WebSocket client for real-time events | Dart-native WebSocket implementation. Connects to Protect's `wss://` updates endpoint for smart detection events (baby crying). |
| flutter_secure_storage | ^10.0+ | Credential storage | Stores Unifi Protect API key. On macOS without signing, falls back to in-memory storage (see memory note). |
| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/proxy/protect/integration/v1/cameras` | GET | List cameras (X-API-Key auth) |
| `/proxy/protect/integration/v1/cameras/{id}/rtsps-stream` | GET | Get RTSPS URLs per quality (high/medium/low) |
| `/proxy/protect/api/bootstrap` | GET | Full NVR data — **does NOT work with X-API-Key** (returns 500), needs cookie auth |
| `wss://.../proxy/protect/ws/updates?lastUpdateId=X` | WS | Real-time smart detection events |
- RTSPS URLs use per-channel aliases (e.g. `rtsps://{nvr_ip}:7441/{alias}?enableSrtp`), NOT camera IDs
- Get aliases from the `/cameras/{id}/rtsps-stream` integration endpoint
- RTSP must be enabled per-camera in Unifi Protect settings (Advanced > RTSP)
### UI Framework
| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| Flutter Material 3 | (built-in) | UI components | Default Flutter UI. Simple app with sliders, lists, and status indicators. No need for a custom design system. |
### State Management
| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| riverpod | ^2.6+ | Application state management | Handles async state well (stream connections, API responses). Provider-based architecture maps cleanly to this app's needs: auth state, camera list, player state, volume levels, connection status. |
### Audio Level Metering
| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| Bitrate-based activity detection | -- | Visual audio activity indicator | The prebuilt media_kit FFmpeg does NOT include audio analysis filters (`ebur128`, `astats`, `aformat`, `stereotools` all missing). Audio activity is estimated by polling `audio-bitrate` changes via mpv properties. `audio-pts` tracks stream flow (silence detection). |
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
- **Android:** Full functionality. media_kit uses libmpv natively for RTSP.
- **Web:** Cannot play RTSP streams. Would require a server-side proxy converting RTSP to HLS/WebSocket, adding 5-30 seconds of latency. This defeats the purpose for a baby monitor.
## Installation
# Core dependencies
# Dev dependencies
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
<!-- GSD:stack-end -->

<!-- GSD:conventions-start source:CONVENTIONS.md -->
## Conventions

### Defensive error handling — streams must never break

This is a baby monitor. Parents fall asleep trusting it. **No exception may kill a running audio stream.**

- Wrap all non-critical operations (metadata polling, UI updates, filter setup, property reads) in try/catch. Log the error with `appLog` and continue.
- Only propagate exceptions that genuinely prevent the stream from functioning (e.g., failed `player.open()`).
- Never call `setProperty` with a filter/value that hasn't been verified to work on this FFmpeg build. If a filter might not exist, catch the async failure via the error stream and recover.
- State update failures (e.g., index out of range during a poll) must not bubble up — catch, log, skip.
- Prefer degraded functionality over crash: if a feature (metering, debug info, video toggle) fails, disable that feature silently and keep audio playing.

### media_kit FFmpeg build limitations

The prebuilt `media_kit_libs_video` (macOS) ships a stripped FFmpeg. These are **known missing**:
- Audio filters: `ebur128`, `astats`, `aformat`, `stereotools`, `pan` (via lavfi)
- The `lavfi` wrapper cannot pass `|` characters via `setProperty` — mpv parses them as filter chain separators before FFmpeg sees them. Neither `\|`, `[...]` quoting, nor `graph="..."` quoting works.
- L/R stereo panning is **not currently implemented** due to the above. Deferred to a future phase (may require custom FFmpeg build).

Do NOT attempt to use lavfi audio filters without first verifying they exist in the build. A failed filter via `setProperty` kills the audio stream asynchronously (mpv error: "Audio filter initialized failed!" → "No video or audio streams selected").

### Authentication

Uses the official Protect integration API with `X-API-Key` header (not cookie/CSRF login). The bootstrap API (`/proxy/protect/api/bootstrap`) does NOT accept API key auth — returns 500.
<!-- GSD:conventions-end -->

<!-- GSD:architecture-start source:ARCHITECTURE.md -->
## Architecture

Architecture not yet mapped. Follow existing patterns found in the codebase.
<!-- GSD:architecture-end -->

<!-- GSD:workflow-start source:GSD defaults -->
## GSD Workflow Enforcement

Before using Edit, Write, or other file-changing tools, start work through a GSD command so planning artifacts and execution context stay in sync.

Use these entry points:
- `/gsd:quick` for small fixes, doc updates, and ad-hoc tasks
- `/gsd:debug` for investigation and bug fixing
- `/gsd:execute-phase` for planned phase work

Do not make direct repo edits outside a GSD workflow unless the user explicitly asks to bypass it.
<!-- GSD:workflow-end -->



<!-- GSD:profile-start -->
## Developer Profile

> Profile not yet configured. Run `/gsd:profile-user` to generate your developer profile.
> This section is managed by `generate-claude-profile` -- do not edit manually.
<!-- GSD:profile-end -->
