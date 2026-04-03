# Phase 2: RTSP Audio Streaming - Research

**Researched:** 2026-04-03
**Domain:** RTSP audio playback via media_kit (libmpv), stereo panning, Flutter state management
**Confidence:** HIGH

## Summary

Phase 2 adds the core audio pipeline: connecting to two Unifi Protect cameras via RTSP, extracting audio-only streams, and providing per-camera volume control with stereo panning. The technology stack is well-suited -- media_kit (built on libmpv/FFmpeg) supports RTSP natively, provides per-Player volume control, and exposes low-level mpv properties through its `NativePlayer` API for stereo panning via the lavfi pan audio filter.

The key technical challenge is stereo panning (STRM-03). mpv removed its built-in `--balance` property in v0.26.0 with no replacement. The proven alternative is applying an FFmpeg lavfi `pan` audio filter at runtime via `NativePlayer.setProperty('af', ...)`. This approach is well-documented in the mpv community and maps cleanly to media_kit's property API.

**Primary recommendation:** Use two independent `Player` instances (one per camera) with `media_kit_libs_audio` for audio-only native libraries. Disable video decoding via `NativePlayer.setProperty('vid', 'no')`. Implement volume via `Player.setVolume()` and stereo panning via lavfi pan filter on the `af` property. Add `rtsp` and `rtsps` to `protocolWhitelist` in PlayerConfiguration.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| STRM-01 | App extracts and plays audio-only from 2 RTSP streams simultaneously (no video decoding) | media_kit supports multiple Player instances, audio-only libs exclude video codecs, `vid=no` property disables video decoding |
| STRM-02 | User can adjust volume independently per camera via sliders | `Player.setVolume(double)` controls per-player volume (0.0-100.0), independent per instance |
| STRM-03 | User can pan each camera's audio between left/right stereo channels | lavfi pan filter via `NativePlayer.setProperty('af', 'lavfi=[pan=stereo|FL=...|FR=...]')` -- mpv's balance was removed in 0.26.0, pan filter is the replacement |
</phase_requirements>

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| media_kit | 1.2.6 | RTSP stream connection, audio decoding, playback | Built on libmpv/FFmpeg. Supports RTSP, multiple simultaneous Player instances, per-player volume. Exposes NativePlayer for mpv property access. |
| media_kit_libs_audio | 1.0.7 | Platform-agnostic audio-only dependency declaration | Meta-package that pulls in correct platform libs. Must NOT mix with media_kit_libs_video. |
| media_kit_libs_macos_audio | 1.1.4 | macOS native audio libraries (libmpv) | Required for macOS dev target (PLAT-01). Contains audio-only libmpv build. |
| media_kit_libs_android_audio | 1.3.8 | Android native audio libraries (libmpv) | Required for future Android target (Phase 3). Include now to avoid dependency conflicts later. |
| media_kit_native_event_loop | 1.0.9 | Native event loop for macOS/Windows | Required on macOS to prevent UI freezes. Handles native libmpv event dispatch. |

### Supporting (already in project)

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| flutter_riverpod | 3.3.1 | State management | Audio player state, volume levels, panning state, connection status |
| go_router | 17.1.0 | Navigation | Already routes to /monitoring screen |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Two Players for mixing | Manual PCM mixing | Unnecessary complexity. OS audio subsystem mixes the two Player outputs. Two Players IS the mixer. |
| lavfi pan for stereo | Separate audio output devices | Not portable, not available on mobile |
| media_kit | just_audio + just_audio_media_kit | just_audio wraps media_kit but adds abstraction that hides NativePlayer access needed for pan filter |

**Installation:**
```bash
flutter pub add media_kit media_kit_libs_audio media_kit_native_event_loop
flutter pub add media_kit_libs_macos_audio media_kit_libs_android_audio
```

## Architecture Patterns

### Recommended Project Structure
```
lib/
  features/
    monitoring/
      models/
        player_state.dart          # Per-camera player state (volume, pan, status)
      providers/
        audio_player_provider.dart # Riverpod provider managing two Player instances
      screens/
        monitoring_screen.dart     # Main UI with volume sliders, pan controls
      widgets/
        camera_audio_card.dart     # Per-camera control card (volume slider, pan, status)
```

### Pattern 1: Two Independent Player Instances
**What:** Create one `Player` per selected camera. Each Player connects to its own RTSP URL and has independent volume/pan control.
**When to use:** Always -- this is the architecture for this app.
**Example:**
```dart
// Source: media_kit pub.dev docs + NativePlayer API docs
import 'package:media_kit/media_kit.dart';

// In main.dart initialization:
MediaKit.ensureInitialized();

// Creating audio-only RTSP player:
final player = Player(
  configuration: const PlayerConfiguration(
    // Add rtsp/rtsps to whitelist (not in defaults)
    protocolWhitelist: ['udp', 'rtp', 'tcp', 'tls', 'data', 'file',
                        'http', 'https', 'crypto', 'rtsp', 'rtsps'],
  ),
);

// Disable video decoding at mpv level
final nativePlayer = player.platform as NativePlayer;
await nativePlayer.setProperty('vid', 'no');

// Low-latency profile for live streams
await nativePlayer.setProperty('profile', 'low-latency');

// Open RTSP stream
await player.open(Media('rtsp://${nvrHost}:7447/${cameraId}'));

// Volume control (0.0 to 100.0)
await player.setVolume(75.0);
```

### Pattern 2: Stereo Panning via lavfi Pan Filter
**What:** Use mpv's `af` property to apply an FFmpeg lavfi pan filter that distributes a mono/stereo source across left/right channels.
**When to use:** For STRM-03 stereo panning feature.
**Example:**
```dart
// Source: mpv af.rst docs + FFmpeg pan filter docs + wiiaboo/mpv-scripts audio-balance.lua
// pan value: -1.0 (full left) to 0.0 (center) to 1.0 (full right)

Future<void> setPan(NativePlayer nativePlayer, double pan) async {
  // pan is -1.0 (left) to 1.0 (right)
  // Convert to left/right gains
  final leftGain = (1.0 - pan) / 2.0;   // 1.0 at full left, 0.0 at full right
  final rightGain = (1.0 + pan) / 2.0;  // 0.0 at full left, 1.0 at full right

  final filter = 'lavfi=[pan=stereo|FL=${leftGain.toStringAsFixed(3)}*c0|'
                 'FR=${rightGain.toStringAsFixed(3)}*c0]';
  await nativePlayer.setProperty('af', filter);
}

// Usage: pan nursery to left ear
await setPan(nativePlayer, -0.7);  // mostly left
```

**Important notes on pan filter:**
- `c0` assumes mono input from camera mic (single channel). If the RTSP stream is stereo, use `c0+c1` to mix both input channels.
- The filter string must be set as a whole -- each `setProperty('af', ...)` replaces the previous filter chain.
- Filter syntax: `pan=<output_layout>|<output_channel>=<gain>*<input_channel>|...`

### Pattern 3: RTSP URL Construction
**What:** Build RTSP URL from NVR host and camera ID.
**When to use:** When opening streams for selected cameras.
**Example:**
```dart
// Source: Unifi community + CLAUDE.md
// Unencrypted RTSP (simpler, works on LAN):
String rtspUrl(String nvrHost, String cameraId) =>
    'rtsp://$nvrHost:7447/$cameraId';

// Encrypted RTSPS (if needed):
String rtspsUrl(String nvrHost, String cameraId) =>
    'rtsps://$nvrHost:7441/${cameraId}?enableSrtp';
```

**Note:** RTSP must be enabled per-camera in Unifi Protect settings (Advanced > RTSP). The camera ID used in the URL is the same `id` field from the Protect API `/cameras` endpoint (already in `ProtectCamera.id`).

### Pattern 4: Riverpod Provider for Audio State
**What:** AsyncNotifier managing two Player instances with volume/pan state.
**When to use:** Managing the monitoring screen lifecycle.
**Example:**
```dart
// Conceptual structure
class AudioPlayerState {
  final Map<String, PlayerStatus> players; // cameraId -> status
  // PlayerStatus contains: isPlaying, volume, pan, connectionState
}

class AudioPlayerNotifier extends AsyncNotifier<AudioPlayerState> {
  final Map<String, Player> _players = {};

  Future<void> startMonitoring(List<ProtectCamera> cameras, String nvrHost) async {
    for (final camera in cameras) {
      final player = Player(configuration: ...);
      // configure audio-only, low-latency
      _players[camera.id] = player;
      await player.open(Media(rtspUrl(nvrHost, camera.id)));
    }
  }

  @override
  Future<AudioPlayerState> build() async => AudioPlayerState.initial();

  // dispose players when leaving monitoring screen
}
```

### Anti-Patterns to Avoid
- **Mixing media_kit_libs_video and media_kit_libs_audio:** These are mutually exclusive. Using both causes build failures and bloats the binary with video codecs.
- **Using Player.setVolume for panning:** Volume is a single scalar (0-100). Panning requires the af (audio filter) property on NativePlayer.
- **Not disposing Players:** Each Player allocates native resources (libmpv instance). Must dispose when leaving monitoring screen or stopping playback.
- **Setting mpv properties before Player is ready:** Always use `waitForInitialization: true` (default) on NativePlayer property calls, or use PlayerConfiguration's `ready` callback.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Audio mixing of two streams | PCM sample mixer | Two Player instances + OS audio subsystem | OS handles sample mixing. Two independent players IS the mixer. |
| RTSP protocol handling | Custom RTSP client | media_kit (libmpv/FFmpeg) | RTSP is complex (DESCRIBE/SETUP/PLAY, RTP/RTCP, codec negotiation). FFmpeg handles all of it. |
| Stereo panning | Custom audio output routing | mpv lavfi pan filter | Pan filter runs in the FFmpeg audio pipeline natively, no Dart-side audio processing needed. |
| Audio-only stream extraction | FFmpeg CLI wrapper | media_kit with `vid=no` property | media_kit already wraps libmpv. Setting `vid=no` skips video decoding entirely. |
| Low-latency live streaming | Custom buffering logic | mpv `low-latency` profile | The profile configures multiple mpv internals (demuxer, cache, sync) optimally. |

**Key insight:** media_kit + NativePlayer property access gives us the full power of mpv/FFmpeg without writing native code. The audio filter pipeline handles panning, and the OS audio subsystem handles mixing two player outputs.

## Common Pitfalls

### Pitfall 1: Protocol Whitelist Missing RTSP
**What goes wrong:** Player fails to open RTSP URLs with a protocol error.
**Why it happens:** media_kit's default `protocolWhitelist` includes `udp`, `rtp`, `tcp`, `tls` etc. but does NOT include `rtsp` or `rtsps`.
**How to avoid:** Explicitly add `'rtsp'` and `'rtsps'` to `PlayerConfiguration.protocolWhitelist`.
**Warning signs:** "Protocol not on whitelist" error in mpv logs.

### Pitfall 2: Self-Signed Certificate Rejection for RTSPS
**What goes wrong:** RTSPS connections fail with TLS certificate validation errors.
**Why it happens:** Unifi Protect consoles use self-signed certificates. libmpv/FFmpeg may reject them.
**How to avoid:** Use unencrypted RTSP (port 7447) on LAN -- it's same-network only, no security risk. If RTSPS is needed, set `--tls-verify=no` via NativePlayer property. Start with RTSP for simplicity.
**Warning signs:** TLS handshake failure in mpv logs.

### Pitfall 3: High Latency on RTSP Streams
**What goes wrong:** 2+ second audio delay from live.
**Why it happens:** Default mpv configuration buffers aggressively for smooth playback (designed for video files, not live streams).
**How to avoid:** Set `profile=low-latency` via NativePlayer. This configures cache, demuxer threading, and sync mode for live streaming.
**Warning signs:** Noticeable delay when testing against known sounds.

### Pitfall 4: Pan Filter Syntax Errors
**What goes wrong:** Setting the `af` property fails silently or produces no audio.
**Why it happens:** The lavfi filter string has strict syntax. Missing brackets, wrong channel names, or float formatting issues.
**How to avoid:** Build the filter string programmatically with proper escaping. Test with known values first (full left, center, full right). Log the exact filter string being set.
**Warning signs:** No audio output after setting pan, mpv error log messages about filter chain.

### Pitfall 5: Camera Mic Not Enabled
**What goes wrong:** RTSP stream connects but produces silence.
**Why it happens:** Unifi Protect cameras have microphone disabled by default. RTSP stream may still open but deliver no audio data.
**How to avoid:** Check `ProtectCamera.isMicEnabled` (already in the model) and warn the user if a selected camera has mic disabled.
**Warning signs:** Stream appears connected but no audio heard. The `isMicEnabled` field is `false`.

### Pitfall 6: Not Disposing Player Resources
**What goes wrong:** Memory leaks, audio continues after leaving monitoring screen.
**Why it happens:** Each Player allocates a native libmpv instance. Without explicit disposal, resources persist.
**How to avoid:** Dispose players in the Riverpod provider's dispose/close lifecycle. Use `ref.onDispose()` to clean up.
**Warning signs:** Audio keeps playing after navigating away, memory usage grows over time.

## Code Examples

### Full Audio Player Setup
```dart
// Source: media_kit pub.dev docs + NativePlayer API reference
import 'package:media_kit/media_kit.dart';

Future<Player> createAudioPlayer(String rtspUrl) async {
  final player = Player(
    configuration: const PlayerConfiguration(
      protocolWhitelist: [
        'udp', 'rtp', 'tcp', 'tls', 'data', 'file',
        'http', 'https', 'crypto', 'rtsp', 'rtsps',
      ],
      // Reduce buffer for live streaming
      bufferSize: 2 * 1024 * 1024, // 2MB instead of default 32MB
    ),
  );

  final native = player.platform as NativePlayer;

  // Audio-only: disable video decoding
  await native.setProperty('vid', 'no');

  // Low-latency for live RTSP
  await native.setProperty('profile', 'low-latency');
  await native.setProperty('cache', 'no');
  await native.setProperty('demuxer-lavf-o', 'rtsp_transport=tcp');

  // Open the stream
  await player.open(Media(rtspUrl));

  return player;
}
```

### Stereo Pan Control
```dart
// Source: FFmpeg pan filter docs + mpv af.rst
// Converts a pan value (-1.0 to 1.0) into an mpv af property string.
// Assumes mono input from camera microphone.

String buildPanFilter(double pan) {
  // Clamp to valid range
  final p = pan.clamp(-1.0, 1.0);
  final leftGain = ((1.0 - p) / 2.0).toStringAsFixed(3);
  final rightGain = ((1.0 + p) / 2.0).toStringAsFixed(3);
  return 'lavfi=[pan=stereo|FL=${leftGain}*c0|FR=${rightGain}*c0]';
}

Future<void> applyPan(NativePlayer native, double pan) async {
  final filter = buildPanFilter(pan);
  await native.setProperty('af', filter);
}
```

### Volume + Pan Combined State
```dart
// Per-camera audio state
class CameraAudioState {
  final double volume;  // 0.0 to 100.0
  final double pan;     // -1.0 (left) to 1.0 (right)
  final bool isPlaying;
  final String? error;

  const CameraAudioState({
    this.volume = 100.0,
    this.pan = 0.0,
    this.isPlaying = false,
    this.error,
  });
}
```

### Monitoring Screen UI Layout (Conceptual)
```dart
// Per-camera card with volume slider and pan slider
Column(
  children: [
    Text(camera.name ?? 'Camera'),
    // Volume: horizontal slider 0-100
    Slider(value: volume, min: 0, max: 100, onChanged: setVolume),
    // Pan: horizontal slider -1.0 to 1.0, center-notched
    Row(
      children: [
        Text('L'),
        Expanded(
          child: Slider(value: pan, min: -1.0, max: 1.0, onChanged: setPan),
        ),
        Text('R'),
      ],
    ),
  ],
)
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| mpv `--balance` property | Removed in mpv 0.26.0, use lavfi pan filter | mpv 0.26.0 (2017) | Must use af property with pan filter for stereo balance |
| media_kit_libs_audio (single package) | Platform-specific packages (macos_audio, android_audio) | media_kit 1.x | Must add per-platform audio lib packages |

**Deprecated/outdated:**
- `mpv --balance`: Removed in mpv 0.26.0 with no built-in replacement. Use `--af=lavfi=[pan=stereo|...]` instead.

## Open Questions

1. **Camera audio channel layout**
   - What we know: Unifi Protect cameras typically have mono microphones.
   - What's unclear: Whether the RTSP stream delivers mono or stereo audio format.
   - Recommendation: Build pan filter assuming mono (`c0`). If stereo is detected, adjust to `c0+c1`. Test with actual camera stream in first implementation task.

2. **RTSP transport protocol (TCP vs UDP)**
   - What we know: mpv defaults to UDP for RTP, but TCP is more reliable on some networks.
   - What's unclear: Which works better with Unifi Protect NVR.
   - Recommendation: Default to TCP via `demuxer-lavf-o=rtsp_transport=tcp` for reliability. UDP can be tried for lower latency if needed.

3. **media_kit RTSP audio-only stability**
   - What we know: STATE.md flags this as "untested for this use case". media_kit with RTSP for video is well-documented.
   - What's unclear: Long-term stability of audio-only RTSP streams (Phase 4 concern, but worth noting).
   - Recommendation: Phase 2 focuses on basic playback. Reliability/reconnection is Phase 4 scope.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Flutter | Framework | Yes | 3.41.6 | -- |
| Dart | Language | Yes | 3.9.2+ (via Flutter) | -- |
| Unifi Protect NVR | RTSP source | Assumed (user's hardware) | -- | Cannot test without hardware |
| Network (LAN) | RTSP connectivity | Assumed | -- | -- |

**Missing dependencies with no fallback:**
- None that block development. media_kit packages are pub.dev dependencies that will be fetched automatically.

**Notes:**
- macOS entitlements already include `com.apple.security.network.client` (needed for RTSP network access).
- Actual RTSP testing requires a running Unifi Protect NVR with cameras that have RTSP enabled.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | flutter_test (built-in) + mockito 5.5.0 |
| Config file | None (uses flutter defaults) |
| Quick run command | `flutter test` |
| Full suite command | `flutter test` |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| STRM-01 | Player creation with audio-only config, vid=no property set | unit | `flutter test test/features/monitoring/audio_player_test.dart -x` | No -- Wave 0 |
| STRM-01 | RTSP URL construction from NVR host + camera ID | unit | `flutter test test/features/monitoring/rtsp_url_test.dart -x` | No -- Wave 0 |
| STRM-02 | Volume state changes propagate to Player.setVolume | unit | `flutter test test/features/monitoring/audio_player_test.dart -x` | No -- Wave 0 |
| STRM-03 | Pan filter string generation (left/center/right boundary values) | unit | `flutter test test/features/monitoring/pan_filter_test.dart -x` | No -- Wave 0 |
| STRM-03 | Pan value clamping (-1.0 to 1.0 range) | unit | `flutter test test/features/monitoring/pan_filter_test.dart -x` | No -- Wave 0 |

**Note:** Actual RTSP stream playback cannot be unit-tested (requires real NVR). Unit tests cover: URL construction, pan filter string building, state management logic, player configuration. Integration testing is manual (play audio from real cameras).

### Sampling Rate
- **Per task commit:** `flutter test`
- **Per wave merge:** `flutter test`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `test/features/monitoring/pan_filter_test.dart` -- covers STRM-03 pan filter string generation
- [ ] `test/features/monitoring/rtsp_url_test.dart` -- covers STRM-01 URL construction
- [ ] `test/features/monitoring/audio_player_test.dart` -- covers STRM-01 player config, STRM-02 volume state

## Project Constraints (from CLAUDE.md)

- **Platform**: Android primary, macOS for dev -- media_kit packages must cover both
- **Audio only**: Must NOT decode video -- use `media_kit_libs_audio` (not video), set `vid=no` property
- **Reliability**: Must survive overnight -- Player resource management and disposal are critical (Phase 4 hardening, but clean design now)
- **media_kit is the chosen RTSP library** -- do not explore alternatives (locked in CLAUDE.md)
- **Two media_kit Players IS the mixer** -- do not build custom PCM mixing (locked in CLAUDE.md)
- **riverpod for state management** -- manual providers (AsyncNotifier), not riverpod_generator (Dart 3.9.2 incompatibility noted in STATE.md)
- **Existing patterns**: GoRouter routing, feature-based folder structure, in-memory storage for debug (flutter_secure_storage issue on unsigned macOS)

## Sources

### Primary (HIGH confidence)
- [media_kit pub.dev](https://pub.dev/packages/media_kit) -- v1.2.6, Player API, PlayerConfiguration
- [NativePlayer API docs](https://pub.dev/documentation/media_kit/latest/media_kit/NativePlayer-class.html) -- setProperty, getProperty, observeProperty, command methods
- [Player API docs](https://pub.dev/documentation/media_kit/latest/media_kit/Player-class.html) -- setVolume, open, dispose, platform access
- [PlayerConfiguration API docs](https://pub.dev/documentation/media_kit/latest/media_kit/PlayerConfiguration-class.html) -- protocolWhitelist, bufferSize, vo defaults
- [mpv interface-changes.rst](https://github.com/mpv-player/mpv/blob/master/DOCS/interface-changes.rst) -- balance removed in 0.26.0
- [mpv af.rst](https://github.com/mpv-player/mpv/blob/master/DOCS/man/af.rst) -- lavfi filter syntax
- [FFmpeg pan filter docs](https://ffmpeg.org/ffmpeg-filters.html) -- pan=stereo channel mixing syntax

### Secondary (MEDIUM confidence)
- [media_kit RTSP latency issue #799](https://github.com/media-kit/media-kit/issues/799) -- low-latency profile recommendation, verified with mpv docs
- [wiiaboo/mpv-scripts audio-balance.lua](https://github.com/wiiaboo/mpv-scripts/blob/master/audio-balance.lua) -- pan filter implementation reference
- [Unifi Protect RTSP community thread](https://community.ui.com/questions/Access-UniFi-Protect-camera-RTSP-stream/b1ba4c62-0764-4223-80d0-650768b0f87f) -- RTSP port 7447, RTSPS port 7441

### Tertiary (LOW confidence)
- Camera audio channel layout (mono vs stereo) -- assumed mono based on typical IP camera specs, needs validation with actual stream

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- media_kit is the locked choice per CLAUDE.md, versions verified against pub.dev registry
- Architecture: HIGH -- two Player instances pattern is documented and recommended in CLAUDE.md, NativePlayer property API is verified
- Stereo panning: MEDIUM -- lavfi pan filter approach is proven in mpv ecosystem but untested specifically through media_kit's NativePlayer.setProperty in this context
- Pitfalls: HIGH -- protocol whitelist, self-signed certs, latency are well-documented issues in media_kit GitHub issues

**Research date:** 2026-04-03
**Valid until:** 2026-05-03 (stable domain, media_kit 1.x is mature)
