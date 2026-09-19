<!-- GSD:project-start source:PROJECT.md -->
## Project

**Roomtone**

A baby monitor app that connects to Unifi Protect cameras, extracts audio from RTSP streams, and lets a parent listen to two rooms simultaneously with per-camera volume mixing and optional video preview. Designed to run reliably overnight on Android with the screen off — something the Unifi app and VLC can't do.

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
| Flutter | 3.47.5 (pinned in CI and the session hook) | Cross-platform app framework | Only viable option that covers Android (primary) + web (nice-to-have) with strong native interop for audio/foreground services. React Native's RTSP ecosystem is worse. Native Android-only kills the web goal. |
| Dart | 3.12+ | Application language | Comes with Flutter. Strong async/stream primitives fit the event-driven architecture (WebSocket listeners, audio streams). |
### RTSP Audio Playback
| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| media_kit | ^1.2.6 | RTSP stream connection and audio decoding | Built on libmpv (which uses FFmpeg internally). Supports RTSP natively, handles multiple simultaneous Player instances, and provides volume control per-player. This is the core of the app. |
| media_kit_video | ^1.2.6 | Video rendering for optional preview | Provides `Video` widget and `VideoController`. Used for optional video preview toggle — off by default, video disabled via `vid=no` mpv property. |
| media_kit_libs_video | ^1.0.6 | Full native libraries (FFmpeg with RTSP demuxer) | **Must use video libs, not audio-only.** The `media_kit_libs_audio` build strips the RTSP/RTSPS demuxer (`Unknown lavf format rtsp` error). The video libs include all protocol demuxers. Video decoding is disabled at runtime via `vid=no` to save CPU. |
### Background Execution
| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| flutter_foreground_task | ^11.0.3 | Android foreground service with persistent notification | Most actively maintained foreground service package. Supports two-way communication between service and UI isolate. Auto-resume on boot. Provides `mediaPlayback` foreground service type required by Android 14+. |
| audio_service | ^0.18.19 | Media session integration (lock screen, notification controls) | Integrates with Android's MediaSession for play/pause/volume on lock screen and notification area. Provides WAKE_LOCK. Complements flutter_foreground_task for the media playback use case. |
### Unifi Protect API Integration
| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| dio | ^5.11+ | HTTP client for Protect API | Industry-standard Flutter HTTP client. Supports interceptors for auth token refresh, cookie management, and self-signed certificate handling (Unifi consoles use self-signed certs). |
| web_socket_channel | ^3.0+ | WebSocket client for real-time events | Dart-native WebSocket implementation. Connects to Protect's `wss://` updates endpoint for smart detection events (baby crying). |
| flutter_secure_storage | ^11.2+ | Credential storage | Stores Unifi Protect API key. On macOS without signing, falls back to in-memory storage (see memory note). |
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
| riverpod | ^3.4+ | Application state management | Handles async state well (stream connections, API responses). Provider-based architecture maps cleanly to this app's needs: auth state, camera list, player state, volume levels, connection status. |
### Audio Level Metering
| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| PCM tap level metering (`ao=pcm` → named pipe) | -- | Visual audio activity indicator | The prebuilt media_kit FFmpeg has NO audio analysis filters on ANY platform: the Android build is configured with `--disable-filters` and re-enables only `overlay`/`equalizer` (verified by reading the `libmpv.so` configure string), and macOS lacks `ebur128`/`astats`/`aformat` too. Encoded AAC bitrate barely tracks loudness (near-CBR). So the meter is a SECOND, silent mpv `Player` per camera (`PcmLevelTap`, `lib/features/monitoring/services/pcm_level_tap.dart`) with `ao=pcm`, `ao-pcm-file=<FIFO>`, `audio-format=s16`, `audio-channels=mono`, `audio-samplerate=8000`; Dart reads the FIFO non-blocking through libc FFI (`PcmFifo`) every 250 ms and `PcmLevelMeter` computes short-term RMS in dBFS. `AudioLevelTracker` turns that into a noise-floor-relative 0..1 level (rolling 5-min floor/ceiling, fast attack / slow release) that drives the card border, level bar and 60 s waveform. If the tap cannot start (no FIFO support, console refuses the extra session) the level falls back to the `audio-bitrate` proxy; the main player is never touched. `audio-pts` tracks stream flow (silence detection). |
### Supporting Libraries
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| connectivity_plus | ^7.3+ | Network connectivity monitoring | Detect WiFi disconnection for auto-reconnect logic |
| flutter_local_notifications | ^22.3+ | Push notifications | Cry detection alerts when app is in background |
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
| Flutter >= 3.44.0 / Dart >= 3.12.0 | Required by flutter_foreground_task 11.x, go_router 18.x and record 7.x |
| Kotlin Gradle plugin 2.3.20 | Flutter 3.47's template version; configured in `android/settings.gradle.kts`. Kotlin 2.2+ removed the `kotlinOptions {}` block — `android/app/build.gradle.kts` uses `kotlin { compilerOptions { jvmTarget } }` |
| Gradle >= 8.14.0 | Required by the Flutter 3.47+ Gradle plugin (the release runner tracks Flutter `stable`; 8.13 broke the v1.13.0 APK build). Wrapper pinned in `android/gradle/wrapper/gradle-wrapper.properties`. |
| AGP 8.11.1 | Hard minimum of the Flutter 3.47+ Gradle plugin. Deliberately NOT yet on AGP 9 (Flutter's template default): AGP 9 switches to built-in Kotlin and the new DSL, a migration that must be verified with a real Android build. Set in `android/settings.gradle.kts`. |
| Android minSdk >= 24 | Flutter default; also required by record_android, flutter_secure_storage 11 and flutter_local_notifications 22 |
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

### Commits and PR titles — Conventional Commits (release-please)

Releases and the CHANGELOG are generated by release-please from commit messages on `main`. PRs are **squash-merged with the PR title as the commit message**, so the PR title is what release-please parses — a non-conventional title means the change is silently dropped from the CHANGELOG and version bump.

- **PR titles MUST be Conventional Commits formatted**: `type(scope): description`, e.g. `feat(help): add setup guides`. This is the single most important rule.
- **Creating a PR — always derive title and description from the whole branch:**
  1. Before opening any PR, review ALL commits on the branch with `git log --oneline main..HEAD` (and optionally `git diff main...HEAD --stat` to see the full changeset). The FIRST commit is usually a `docs(...): pre-dispatch plan` GSD planning commit and MUST NOT be used as the title.
  2. Compose the PR title as a single Conventional Commits line (`type(scope): description`) describing the OVERALL change across all commits — the type reflects the substantive change (a feature PR is `feat(...)` even if the first commit is `docs:`/`test:`/`chore:`).
  3. Compose the PR description to summarize the whole diff and all meaningful commits, not just one.
  4. ALWAYS pass an explicit title AND body to the PR-creation tool (`gh pr create --title ... --body ...`, or the GitHub MCP `create_pull_request` with explicit `title` and `body`) — never omit them and let GitHub default them from the first commit.
  5. If a PR was already opened with a default title/description, update it (`gh pr edit --title ... --body ...`) rather than leaving it.
- Individual commit messages must follow the same format (CI lints both via `.github/workflows/conventional-commits.yml`; config in `commitlint.config.mjs`).
- Allowed types (mirrors `release-please-config.json`): `feat`, `fix`, `perf`, `refactor`, `docs`, `chore`, `build`, `ci`, `style`, `test`, `revert`.
- `feat` bumps the minor version, `fix`/`perf` bump the patch; a `!` after the type (e.g. `feat!:`) marks a breaking change and bumps the major version.

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

Anything that needs decoded audio (metering, analysis) goes through a separate, disposable `Player` (see `PcmLevelTap`), never the one the parent is listening to — a failure there costs a feature, not the stream.

Paired phone cameras (`CameraSource.peer`, `lib/features/peer/`) stream constant-bitrate PCM16 WAV over HTTP, so the bitrate proxy is blind for them: the tap is their primary meter as well, and the fallback is the dBFS the host phone measures on its own microphone (`/roomtone/v1/status` → `LevelSource.host`), never the bitrate.

### Live edge, latency and stream modes

A live stream's demuxer packet cache can only grow: mpv reads as fast as the network delivers and plays at exactly 1x, so every stall (Doze, audio-focus duck, WiFi hiccup, the NVR's start-up burst) leaves a backlog that nothing drains. Facts verified against the mpv manual, do not re-derive them:

- With `cache=yes`, `demuxer-readahead-secs` is **ignored** (`cache-secs`, default ~1000 s, wins); only `demuxer-max-bytes` bounds the cache. Keep that cap generous so a backlog stays *visible* in `demuxer-cache-duration` instead of backing up into the TCP socket.
- media_kit sets `cache-on-disk=yes` on every player; `_applyPlaybackTuning` pins it to `no`.
- Catch-up is a `speed` nudge (`DriftWatchdog`, `lib/features/monitoring/services/drift_watchdog.dart`): `audio-pitch-correction` auto-inserts mpv's **built-in** `scaletempo2` (mpv C code, not an FFmpeg lavfi filter, so the stripped FFmpeg build is irrelevant). stop+open is the last resort, only past a 10 s hard limit — never the first response to lag.
- `StreamMode.realtime`: `cache-pause=no` (a dropout beats a pause), lavf `fflags=+nobuffer`, trim to ~0.2 s. `StreamMode.buffered`: mpv's native jitter buffer, `cache-pause=yes` + `cache-pause-initial=yes` + `cache-pause-wait=<bufferedDelaySeconds>`, trim back to that depth.
- `audio-buffer` (the "Audio buffer" slider) is the decoded-sample buffer in front of the device. It is unrelated to the packet cache; never compare the two.

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
