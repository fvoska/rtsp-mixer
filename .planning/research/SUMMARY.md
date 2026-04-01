# Project Research Summary

**Project:** RTSP Audio Mixer (Baby Monitor)
**Domain:** Real-time audio streaming with background service reliability
**Researched:** 2026-04-01
**Confidence:** MEDIUM-HIGH

## Executive Summary

This is a niche but well-scoped application: a Flutter/Android app that connects to two Unifi Protect cameras via RTSP, extracts audio-only streams, mixes them with per-camera volume control, and runs reliably overnight as a foreground service. The expert approach is to treat this as two independent problems: (1) a reliable background audio streaming service, and (2) a Unifi Protect API integration layer. The audio pipeline should stay entirely in native code (via media_kit/libmpv) with Flutter serving only as the UI shell. Two simultaneous Player instances with OS-level audio mixing is the correct architecture -- manual PCM mixing is unnecessary complexity.

The recommended stack is Flutter with media_kit (libmpv/FFmpeg) for RTSP audio, flutter_foreground_task for Android service lifecycle, and a custom Dart Protect API client modeled on the hjdhjd/unifi-protect TypeScript reference. Riverpod manages state. The architecture follows a "thin UI, fat service" pattern where all long-lived resources (players, WebSocket, HTTP client) are owned by the foreground service, not by widgets. This is non-negotiable for overnight reliability.

The three highest risks are: (1) Android OEM battery optimizations killing the foreground service overnight despite correct implementation -- mitigated by battery optimization exemption, OEM-specific user guidance, and a WorkManager watchdog; (2) RTSP streams dropping silently with no error callback -- mitigated by an independent audio-level watchdog and aggressive reconnection with exponential backoff; (3) Unifi Protect's undocumented API breaking with firmware updates -- mitigated by abstracting behind a clean interface and supporting dual auth methods with polling fallback for events. Web support is not viable for audio streaming (browsers cannot do RTSP) and should be deferred entirely.

## Key Findings

### Recommended Stack

Flutter 3.27+ with Dart 3.6+ is the right framework. The key library is **media_kit** (v1.2.6+) built on libmpv/FFmpeg, which handles RTSP natively and offers an audio-only library variant (`media_kit_libs_audio`) that excludes video codecs entirely -- critical for overnight battery life. Two `Player` instances connect to two cameras independently, with `setVolume()` per player and the Android audio subsystem handling actual mixing. No Dart Protect API library exists; we must implement one ourselves using hjdhjd/unifi-protect as reference.

**Core technologies:**
- **Flutter + media_kit**: RTSP audio-only streaming via libmpv -- proven RTSP support, audio-only libs minimize CPU/battery
- **flutter_foreground_task**: Android foreground service with `mediaPlayback` type -- survives indefinitely (no Android 15 time limit)
- **dio + web_socket_channel**: Custom Protect API client -- auth, camera discovery, smart detection events
- **Riverpod**: State management -- handles async interdependent state (auth -> cameras -> players -> status)
- **flutter_secure_storage**: Credential storage via Android Keystore

### Expected Features

**Must have (table stakes):**
- Dual RTSP audio-only streaming with per-camera volume control
- Unifi Protect authentication and camera discovery (no manual URL entry)
- Android foreground service with persistent notification for overnight survival
- Partial wake lock + WiFi lock to prevent OS throttling
- Auto-reconnect with exponential backoff on stream drops
- Connection status indicators per camera
- Credential persistence and auto-connect on launch

**Should have (differentiators vs. VLC/Unifi app):**
- Cry detection via Unifi Protect AI smart detection events + push notification
- Per-camera listening mode (continuous / cry-triggered / off)
- Audio level meters for visual confidence that monitoring is active
- Stream health heartbeat watchdog to catch zombie streams
- Overnight health summary (morning report)

**Defer (v2+):**
- Web companion app (RTSP impossible in browsers)
- Multiple Protect console support
- Audio recording / event playback

### Architecture Approach

Five major subsystems live behind a foreground service that owns all long-lived resources. The UI is a dumb display layer that subscribes to service state via Riverpod. All network connections, players, and event handlers are created and destroyed by the service, never by widgets. This "service-owned resources" pattern is the single most important architectural decision -- without it, the app will silently die when the screen turns off.

**Major components:**
1. **RTSP Stream Manager** -- Two media_kit Player instances, audio-only (vid=no), TCP transport, low-latency buffering
2. **Foreground Service** -- Owns all subsystems, manages Android lifecycle, shows persistent notification, survives screen-off
3. **Protect API Client** -- Auth (dual-method), bootstrap parsing, camera discovery, WebSocket event subscription for cry detection
4. **Health Monitor / Watchdog** -- Polls stream health every 30s, exponential backoff reconnection, notification escalation, WiFi-aware retry pausing
5. **State Bridge** -- Riverpod providers that reactively expose service state to the UI (same isolate, no IPC needed)

### Critical Pitfalls

1. **OEM battery killers terminate foreground services** -- Request battery optimization exemption on first launch. Show OEM-specific instructions (Samsung, Xiaomi). Consider separate-process service. Add WorkManager watchdog as safety net.
2. **RTSP streams drop silently with no error** -- Treat `STATE_ENDED` as an error for live streams. Implement independent audio-level silence detection (30s threshold). Force TCP transport. Exponential backoff reconnection.
3. **Protect API breaks without warning on firmware updates** -- Abstract behind clean interface. Support both cookie and API-key auth. Dual-mode events: WebSocket primary, HTTP polling fallback. Pin and document tested firmware versions.
4. **Memory leaks from long-running streams cause 4AM OOM crash** -- Call `release()` not `stop()` on reconnection. Pre-allocate buffers. Implement periodic clean restart of audio pipeline every 4 hours as a safety net. Monitor native heap size.
5. **Platform channel bottleneck for audio data** -- Keep entire audio pipeline in native code (media_kit handles this). Only send control signals (start/stop/volume) and periodic level-meter updates (10Hz) across the Dart boundary. Never stream raw PCM through MethodChannel.

## Implications for Roadmap

Based on research, suggested phase structure:

### Phase 1: Protect API Client and Project Foundation
**Rationale:** Validates the hardest unknown first -- can we authenticate and discover cameras? Also establishes the foreground service scaffold early since architecture decisions here are irreversible.
**Delivers:** Working Protect auth, camera list from bootstrap API, secure credential storage, project skeleton with foreground service manifest configuration.
**Addresses:** Protect authentication, camera discovery, credential persistence, battery optimization exemption UX.
**Avoids:** Pitfall 3 (Protect API fragility) by building the abstraction layer from the first API call. Pitfall 1 (OEM service killing) by setting up correct manifest and permissions early.

### Phase 2: Single RTSP Audio Stream
**Rationale:** Proves core feasibility -- can media_kit do audio-only RTSP? Must work before adding complexity of dual streams. This is the highest-risk technical validation.
**Delivers:** One camera streaming audio through the foreground service with screen off. Volume control. Basic connection status.
**Uses:** media_kit + media_kit_libs_audio, flutter_foreground_task.
**Implements:** RTSP Stream Manager (single), Foreground Service lifecycle, basic state bridge.
**Avoids:** Pitfall 5 (platform channel bottleneck) by keeping audio in native code from day one. Pitfall 8 (codec negotiation) by testing with real hardware and logging SDP.

### Phase 3: Dual Streams and Audio Mixing
**Rationale:** Second player instance adds the core differentiator -- two rooms simultaneously. Depends on Phase 2 proving single-stream works.
**Delivers:** Two simultaneous audio streams with independent volume sliders. Audio level meters (Android Visualizer API via platform channel). Complete mixing experience.
**Addresses:** Per-camera volume control, audio level meters, dual streaming.
**Avoids:** Pitfall 4 (mixing artifacts) -- two Player instances with OS-level mixing avoids the entire PCM mixing complexity. If OS mixing has issues, escalate to single-AudioTrack approach.

### Phase 4: Smart Detection and Cry Mode
**Rationale:** Requires stable streaming foundation. WebSocket binary protocol parsing is complex and isolated from audio pipeline.
**Delivers:** Cry detection notifications via Protect WebSocket events. Per-camera listening modes (continuous/cry-triggered/off). Cry-triggered stream start/stop lifecycle.
**Implements:** Protect WebSocket event subscription, binary frame parser, local notifications.
**Avoids:** Pitfall 7 (WebSocket binary protocol fragility) by implementing dual-mode (WebSocket + HTTP polling fallback) from the start.

### Phase 5: Reliability Hardening
**Rationale:** All features exist; now make them survive 8+ hours. This phase is about soak testing and edge cases, not new features.
**Delivers:** Health monitor watchdog, enhanced reconnection with WiFi-awareness, notification escalation, memory leak prevention (periodic pipeline restart), overnight soak test validation.
**Addresses:** Stream health heartbeat, overnight health summary, auto-reconnect hardening.
**Avoids:** Pitfall 6 (memory leak OOM) with proactive monitoring and periodic restart. Pitfall 2 (silent drops) with silence-detection watchdog.

### Phase 6: Polish and UX
**Rationale:** Core is reliable. Now improve the experience -- onboarding, error messaging, OEM-specific guidance.
**Delivers:** OEM battery optimization guidance, specific error messages, volume preview during setup, morning health summary screen.
**Addresses:** All UX pitfalls from research. Credential auto-connect, status refinements.

### Phase Ordering Rationale

- **Protect API first** because RTSP URLs come from the bootstrap API. Without it, you cannot connect to cameras. Also validates the highest-uncertainty integration (undocumented API).
- **Single stream before dual** because proving media_kit RTSP audio-only works is the gating technical risk. If it fails, the entire stack choice changes.
- **Foreground service in Phase 2** (not deferred) because the architecture requires audio pipeline ownership by the service. Building it later means rewriting the player lifecycle.
- **Cry detection after streaming** because it depends on a working WebSocket connection that reuses the auth infrastructure, and it is an enhancement to (not a prerequisite for) the core monitoring function.
- **Reliability hardening as a dedicated phase** because overnight bugs only surface under sustained operation. Short development-cycle testing will not catch 4AM OOM crashes or WiFi DHCP renewal drops.

### Research Flags

Phases likely needing deeper research during planning:
- **Phase 2 (Single RTSP Stream):** media_kit audio-only RTSP is not explicitly documented for this use case. Needs spike/prototype to validate. Also: libmpv TCP transport configuration, audio-only mode flags, foreground service integration.
- **Phase 3 (Dual Streams):** Audio level metering approach is LOW confidence. Android Visualizer API via platform channel needs prototyping. May need to defer level meters if too complex.
- **Phase 4 (Smart Detection):** Protect WebSocket binary protocol parsing must be ported from TypeScript. Needs dedicated research into the hjdhjd/unifi-protect source code for frame format.

Phases with standard patterns (skip deep research):
- **Phase 1 (Protect API):** HTTP auth + REST API + JSON parsing is well-understood. The hjdhjd/unifi-protect docs provide clear endpoint reference.
- **Phase 5 (Reliability):** Watchdog patterns, exponential backoff, memory monitoring are standard engineering. No novel research needed.
- **Phase 6 (Polish):** Standard Flutter UI work.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Flutter + media_kit is the clear right choice. No viable alternatives for RTSP audio-only on Android with Flutter. |
| Features | HIGH | Well-defined niche with clear prior art from baby monitor market. Feature boundaries are sharp. |
| Architecture | MEDIUM-HIGH | Service-owned-resources pattern is proven. Uncertainty around audio level metering approach and whether dual Player instances produce clean mixed output on all devices. |
| Pitfalls | HIGH | Multiple sources confirm each pitfall. Android OEM behavior, RTSP silent drops, and Protect API fragility are well-documented risks. |

**Overall confidence:** MEDIUM-HIGH

### Gaps to Address

- **Audio level metering:** LOW confidence. media_kit's audio callback capabilities and Android Visualizer API integration both need prototyping. May need to defer to post-MVP if neither approach works cleanly.
- **Dual Player audio quality:** Not validated that two simultaneous media_kit/libmpv instances produce artifact-free mixed audio on Android. Needs hardware testing in Phase 3.
- **Protect API auth dual-method:** Cookie auth vs API-key auth -- unclear which Protect firmware versions support which. Needs testing against actual NVR during Phase 1.
- **Foreground service + media_kit integration:** flutter_foreground_task runs in the same Dart isolate (confirmed), but media_kit Player lifecycle within that service context is untested. Phase 2 spike required.
- **OEM battery behavior:** Cannot fully validate without testing on Samsung and Xiaomi hardware. Must be part of Phase 5 soak testing.

## Sources

### Primary (HIGH confidence)
- [media_kit on pub.dev](https://pub.dev/packages/media_kit) -- RTSP support, audio-only libs, multiple Player instances
- [flutter_foreground_task on pub.dev](https://pub.dev/packages/flutter_foreground_task) -- Android foreground service with mediaPlayback type
- [Android foreground service types (official)](https://developer.android.com/about/versions/14/changes/fgs-types-required) -- Android 14+ requirements
- [Android Doze and Standby (official)](https://developer.android.com/training/monitoring-device-state/doze-standby) -- Background execution restrictions
- [hjdhjd/unifi-protect GitHub](https://github.com/hjdhjd/unifi-protect) -- Reference Protect API implementation, WebSocket binary protocol

### Secondary (MEDIUM confidence)
- [dontkillmyapp.com](https://dontkillmyapp.com/) -- OEM-specific battery optimization behaviors
- [Home Assistant Protect integration](https://www.home-assistant.io/integrations/unifiprotect/) -- Real-world Protect API usage patterns
- [Unifi community RTSP threads](https://community.ui.com/) -- RTSP port info, camera codec details
- [ExoPlayer RTSP documentation](https://developer.android.com/media/media3/exoplayer/rtsp) -- RTSP codec negotiation details (informative even though we use media_kit)

### Tertiary (LOW confidence)
- Audio level metering via media_kit -- no documented approach, inferred from libmpv capabilities
- Dual media_kit Player mixing quality -- no reports of this specific pattern, inferred from Android audio subsystem behavior

---
*Research completed: 2026-04-01*
*Ready for roadmap: yes*
