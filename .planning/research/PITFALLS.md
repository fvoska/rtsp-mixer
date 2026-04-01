# Pitfalls Research

**Domain:** RTSP audio baby monitor (Flutter/Android, Unifi Protect, overnight background streaming)
**Researched:** 2026-04-01
**Confidence:** HIGH (most pitfalls verified through multiple sources including Android official docs, community reports, and library issue trackers)

## Critical Pitfalls

### Pitfall 1: Android Kills Your Foreground Service Overnight Despite Doing Everything "Right"

**What goes wrong:**
The app streams audio perfectly for 2-4 hours, then silently dies. The parent wakes up to silence, having missed a crying baby. This is the exact failure mode the user already experiences with VLC. Stock Android's Doze mode restricts network access in maintenance windows, but the real killers are OEM-specific battery optimizations. Samsung, Xiaomi, OnePlus, and others layer aggressive app-killing on top of AOSP that ignores foreground service status entirely. Samsung's "Sleeping apps" list (enabled by default) will kill apps after 3 days of not being in foreground. Xiaomi's MIUI can kill foreground services outright.

**Why it happens:**
Developers test on their own device, it works, and they ship. They don't account for the combinatorial explosion of OEM battery behaviors. Android 14+ also requires explicit `foregroundServiceType` declarations in the manifest -- missing this causes immediate crashes, not graceful degradation. Android 15 adds further restrictions: `mediaPlayback` foreground services cannot be started from `BOOT_COMPLETED` receivers.

**How to avoid:**
1. Declare `android:foregroundServiceType="mediaPlayback"` and request `FOREGROUND_SERVICE_MEDIA_PLAYBACK` permission in the manifest. This is non-negotiable for Android 14+.
2. Request battery optimization exemption (`REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`) on first launch. Guide the user through disabling it with a clear explanation ("This app needs to run all night").
3. Run the foreground service in a **separate process** from the main Flutter activity. The official recommendation from dontkillmyapp.com: keep no Activities, Receivers, or other Services in the same process as the foreground service.
4. Use `WakeLock` (partial) to prevent CPU sleep during audio playback. Release it only when the user explicitly stops monitoring.
5. Implement a "heartbeat" mechanism: the service periodically writes a timestamp. A secondary watchdog (WorkManager periodic task) checks if the timestamp is stale and restarts the service if needed.
6. On first launch, detect the OEM and show OEM-specific instructions from dontkillmyapp.com data to disable their custom battery killers.

**Warning signs:**
- Works on Pixel but dies on Samsung/Xiaomi.
- App survives 30-minute tests but dies at the 2-hour mark (Doze deep idle kicks in).
- No crash logs because the OS killed the process externally.
- Audio stops but the notification persists (notification orphaned from dead service).

**Phase to address:**
Phase 1 (Foundation). The foreground service architecture must be correct from day one. Retrofitting a separate-process service is a significant rewrite. The battery optimization exemption UX flow should be in the initial onboarding.

---

### Pitfall 2: RTSP Stream Silently Drops With No Error Callback

**What goes wrong:**
The RTSP connection to a Unifi camera drops (WiFi blip, camera firmware update, NVR restart, DHCP renewal) but the player reports no error. The audio just stops. ExoPlayer's RTSP module uses a timeout-based detection: if no RTP packets arrive for `timeoutMs` (default 8 seconds), it considers the stream ended. But "ended" is not "error" -- the player transitions to `STATE_ENDED` and stops, without triggering error listeners. The parent hears silence and assumes the baby is sleeping, when in reality the stream died.

**Why it happens:**
RTSP is a stateful protocol with separate control (RTSP/TCP) and media (RTP/UDP) channels. The TCP control channel can die while UDP packets keep flowing, or vice versa. Network interruptions don't always produce clean TCP RST packets -- sometimes connections just go stale. ExoPlayer's default behavior is designed for VOD content where "end of stream" is a normal state, not for infinite live streams where silence is always an error.

**How to avoid:**
1. Set a custom timeout via `RtspMediaSource.Factory.setTimeoutMs()` -- use 10-15 seconds (long enough to survive brief WiFi hiccups, short enough to detect real drops).
2. Treat `STATE_ENDED` as an error for live streams. When the player reaches ended state, immediately trigger reconnection logic.
3. Implement an independent audio level monitor: if the decoded audio buffer has been silent (all zeros) for more than 30 seconds, treat it as a potential stream failure and attempt reconnection. Cameras in a baby room are never truly silent -- there's always ambient noise.
4. Use exponential backoff for reconnection: 1s, 2s, 4s, 8s, max 30s. After 5 consecutive failures, show a persistent notification warning the parent.
5. Prefer RTP-over-RTSP (interleaved TCP) over UDP transport. ExoPlayer automatically falls back to TCP after a UDP timeout, but you can force TCP from the start to avoid the fallback delay. TCP is more reliable on home WiFi networks.
6. Send RTSP `OPTIONS` keepalives every 30 seconds to detect control channel death proactively.

**Warning signs:**
- Audio stops but no error toast/notification appears.
- Reconnection only works after manually restarting the app.
- Works on one camera but drops on the other (different firmware versions handle RTSP differently).
- Streams die at exactly the same time each night (NVR scheduled maintenance, DHCP lease renewal).

**Phase to address:**
Phase 2 (RTSP Streaming). The reconnection strategy must be built alongside the initial RTSP implementation, not bolted on later. The "silence detector" can be a Phase 3 hardening feature.

---

### Pitfall 3: Unifi Protect API Is Undocumented and Breaking Changes Ship Without Warning

**What goes wrong:**
The Unifi Protect API has no official public documentation. Every integration (Home Assistant, hjdhjd/unifi-protect, Node-RED) is built on reverse-engineered endpoints. Ubiquiti ships firmware updates that change authentication flows, endpoint signatures, or WebSocket binary protocols without notice. In 2025, the Protect 5.x to 6.x transition broke authentication for every third-party integration simultaneously. The transition from cookie-based auth to API key-based auth (header `X-API-KEY`) happened mid-year and caused widespread outages in Home Assistant installations.

**Why it happens:**
Ubiquiti considers these internal APIs. They are under no obligation to maintain backward compatibility. The WebSocket events protocol uses a custom binary format (not JSON) that requires parsing 8-byte header frames with zlib-compressed payloads. Any change to this binary protocol silently breaks event parsing.

**How to avoid:**
1. Abstract the Protect API behind a clean interface layer. Every API call should go through a single adapter class that can be updated without touching business logic.
2. Support both authentication methods: legacy cookie-based (`/api/auth/login`) and new API key-based (`X-API-KEY` header). Detect which one works and fall back.
3. For RTSP URLs, prefer discovering them via the bootstrap API (`/proxy/protect/api/bootstrap`) rather than hardcoding URL patterns. The bootstrap response contains the actual RTSP URLs the NVR is serving.
4. For smart detection events (baby crying), implement both polling (`/proxy/protect/api/events`) and WebSocket listeners. If the WebSocket dies, fall back to polling. The WebSocket requires keepalive pings; the NVR will close idle connections.
5. Pin to a known-working Protect firmware version in your testing. Document which firmware versions are validated.
6. Monitor the hjdhjd/unifi-protect repository for breaking change reports -- it's the best early-warning system for API changes.

**Warning signs:**
- Auth starts returning 401 after a firmware update with no code changes.
- WebSocket connects but delivers no events (binary protocol changed).
- Bootstrap API returns new JSON structure with missing fields.
- Rate limiting (429) on `/api/auth/login` during reconnection storms.

**Phase to address:**
Phase 2 (Unifi Integration). The abstraction layer must exist from the first API call. Smart detection (WebSocket events) can be Phase 3, but the auth resilience must be immediate.

---

### Pitfall 4: Audio Mixing Two Streams Produces Clicks, Pops, and Buffer Underruns

**What goes wrong:**
Running two simultaneous AudioTrack instances on Android produces stuttering, clicking, or gaps. When both streams are decoded in the same thread, they "take turns" and starve each other. When in separate threads, scheduling jitter causes buffer underruns. The parent hears constant clicking artifacts that make the monitor unusable.

**Why it happens:**
Android's audio pipeline has a well-documented "10ms problem" -- the audio HAL latency varies wildly across devices. Mixing two independent RTSP audio streams means synchronizing two sources with independent clocks, different network jitter profiles, and potentially different sample rates (Unifi cameras typically output AAC-LC at 8kHz or 16kHz, but this varies by model). Buffer underruns occur when the mixer can't fill the output buffer fast enough because one stream is temporarily starved of data.

**How to avoid:**
1. Do NOT use two separate AudioTrack instances. Instead, decode both streams to PCM, mix in software (simple sample addition with volume scaling and clipping), and write to a single AudioTrack. This eliminates scheduling contention entirely.
2. Use a ring buffer (circular buffer) per stream to absorb network jitter. Size it at 200-500ms -- enough to survive WiFi jitter, small enough to keep latency acceptable for a baby monitor (sub-second latency is fine; this isn't a phone call).
3. If streams have different sample rates, resample to a common rate (e.g., 16kHz) before mixing. Use a proper resampler (linear interpolation is not sufficient -- it creates aliasing artifacts).
4. Fill the mix buffer with silence when a stream has no data ready, rather than blocking. A brief silence gap is far less noticeable than a click/pop from an underrun.
5. Use `AudioTrack.setBufferSizeInFrames()` to set a larger buffer (at least 4x the minimum buffer size). Latency is not critical for this use case; stability is.

**Warning signs:**
- Periodic clicking every few seconds (buffer boundary artifacts).
- One stream sounds fine alone but degrades when the second stream starts.
- Audio quality varies by device (different HAL latencies).
- CPU usage spikes correlate with audio glitches (GC pauses in Dart/Java layer).

**Phase to address:**
Phase 2-3 (Audio Pipeline). The single-AudioTrack mixing architecture must be the design from the start. This is a native (Kotlin/C++) component, not implementable purely in Dart.

---

### Pitfall 5: Flutter Platform Channel Bottleneck for Real-Time Audio

**What goes wrong:**
Audio data flows: Camera -> RTSP -> Native decoder -> (Platform Channel) -> Dart -> (Platform Channel) -> Native AudioTrack. Each Platform Channel (MethodChannel) crossing copies all data through serialization. For audio at 16kHz/16-bit, that's 32KB/sec per stream. The serialization overhead is not the bandwidth -- it's the 4 separate memory copies per crossing (documented by Flutter team) and the requirement to run on the platform main thread, which blocks UI rendering.

**Why it happens:**
Developers naturally want to do audio processing in Dart for cross-platform consistency. But MethodChannel is designed for infrequent command/response patterns, not continuous data streaming. EventChannel is slightly better (one-directional streaming) but still serializes everything.

**How to avoid:**
1. Keep the entire audio pipeline in native code. RTSP connection, AAC decoding, PCM mixing, and AudioTrack output should all happen in Kotlin/native without crossing to Dart.
2. Use Platform Channels only for control signals: start/stop stream, set volume (a single float), get audio levels for the UI meter. These are infrequent, small payloads.
3. For the audio level meters (UI feedback), send periodic updates (10Hz is plenty) via EventChannel rather than streaming raw audio data to Dart.
4. If you must share audio data with Dart (e.g., for visualization), use `dart:ffi` with shared memory buffers rather than MethodChannel serialization.
5. Consider a "headless" native service architecture: the Flutter UI connects to a native Android Service that owns the entire audio pipeline. Flutter only sends commands and receives status updates.

**Warning signs:**
- UI jank when audio starts (main thread contention).
- Audio glitches correlate with UI interactions (scrolling the volume slider causes a pop).
- Memory usage grows linearly over time (serialization buffer accumulation).
- Profiler shows excessive time in `StandardMethodCodec.encodeMessage`.

**Phase to address:**
Phase 1 (Architecture Decision). This is a foundational architecture choice. If you start with audio flowing through Dart, migrating to native-only is a complete rewrite of the audio pipeline.

---

### Pitfall 6: Memory Leaks From Long-Running Streams Cause OOM Crash at 4AM

**What goes wrong:**
The app runs fine for 2-3 hours, then crashes with an OutOfMemoryError. Native audio buffers are allocated but never freed on reconnection. Each RTSP reconnection cycle creates new decoder instances without properly releasing the old ones. ExoPlayer's internal `sampleQueue` objects accumulate. After 6-8 hours of occasional reconnections, memory usage has grown from 60MB to 400MB+ and the low memory killer terminates the process.

**Why it happens:**
Long-running streaming apps exercise code paths that short test sessions never hit. Each reconnection is a potential leak source: the old player instance must be fully released (not just stopped) before creating a new one. In Flutter, the Dart GC and Android's native memory are separate heaps -- Dart objects may be collected while their native counterparts leak. The `just_audio` library has documented memory leak issues with `StreamAudioSource` even after calling `dispose()` (GitHub issue #1201).

**How to avoid:**
1. Implement explicit lifecycle management for every native resource. On reconnection: stop player, release player, null all references, create new player. Never reuse a player instance after an error.
2. Use Android's `Debug.getNativeHeapAllocatedSize()` in a periodic health check (every 15 minutes). If native heap grows beyond a threshold (e.g., 200MB), proactively restart the audio pipeline.
3. If using ExoPlayer, call `player.release()` (not just `player.stop()`) on every reconnection. `stop()` retains internal buffers; `release()` frees everything.
4. Implement a "clean restart" mechanism: every 4 hours, gracefully tear down and rebuild the entire audio pipeline from scratch. This is a safety net for leaks you haven't found yet. A 500ms gap every 4 hours is acceptable for a baby monitor.
5. Monitor and log RSS (Resident Set Size) over time in debug builds. If it grows monotonically, you have a leak.

**Warning signs:**
- App crashes at inconsistent times, always after 3+ hours.
- Memory usage in Android Settings shows steady growth.
- Crashes correlate with number of reconnection events, not wall clock time.
- `java.lang.OutOfMemoryError` or native crash in `libmedia.so`.

**Phase to address:**
Phase 3 (Reliability Hardening). The clean resource lifecycle should be in Phase 2, but the periodic restart safety net and memory monitoring are hardening features.

---

### Pitfall 7: Unifi Protect WebSocket Events Use Undocumented Binary Protocol That Breaks Silently

**What goes wrong:**
The cry detection feature depends on receiving smart detection events from the Protect NVR via WebSocket. The WebSocket uses a custom binary protocol (not JSON) with 8-byte header frames and zlib-compressed payloads. The event data must be parsed correctly or events are silently dropped. A Protect firmware update changes the binary format, and your cry detection stops working with zero error messages.

**Why it happens:**
The binary protocol was reverse-engineered by the community (primarily hjdhjd/unifi-protect). It's optimized for bandwidth (the Protect WebUI uses it), not for third-party consumption. Ubiquiti can change the frame structure, compression, or payload schema at any time. The protocol requires sending keepalive pings -- without them, the NVR closes the connection after an idle period. Additionally, using `lastUpdateId` parameter for reconnection is required to avoid missing events during brief disconnections.

**How to avoid:**
1. Use the `hjdhjd/unifi-protect` library as a reference implementation, not as a dependency (it's Node.js). Port the binary parsing logic to Dart/Kotlin.
2. Implement a dual-mode approach: WebSocket for real-time events, HTTP polling (`/proxy/protect/api/events?type=smartDetectZone`) as fallback. If WebSocket parsing fails, automatically switch to polling (every 5-10 seconds).
3. Send WebSocket pings every 30 seconds using the `compress=true` URL parameter on the connection.
4. Log raw WebSocket frames in debug builds so you can diagnose binary protocol changes.
5. Track `lastUpdateId` and use it on reconnection to catch events missed during the disconnect gap.

**Warning signs:**
- WebSocket connects successfully but no events arrive.
- Events worked on firmware version X but stopped on version Y.
- CPU usage spikes during event parsing (decompression of corrupt data).
- Cry events appear in the Protect UI but not in your app.

**Phase to address:**
Phase 3 (Smart Detection). This is the cry detection phase. The dual-mode fallback should be the initial design.

---

### Pitfall 8: ExoPlayer RTSP Codec Negotiation Fails Silently on Non-AAC Audio

**What goes wrong:**
ExoPlayer's RTSP module only supports AAC (mp4a.40.2) and AC3 audio codecs. Unifi cameras may output different AAC profiles (mp4a.40.1 HE-AAC, mp4a.40.30) or PCM/G.711 depending on the camera model and RTSP stream quality setting. When the codec doesn't match, ExoPlayer either fails silently (no audio, no error) or throws a cryptic `ParserException`. The developer spends days debugging what looks like a network issue but is actually a codec mismatch.

**Why it happens:**
RTSP codec negotiation happens via SDP (Session Description Protocol) in the DESCRIBE response. ExoPlayer parses the SDP and creates decoders for supported codecs only. Unsupported codecs are silently skipped. Unifi cameras expose multiple RTSP stream qualities (high/medium/low), each potentially with different audio codecs. The developer tests with one stream quality and ships, only to find the other quality doesn't work.

**How to avoid:**
1. During camera setup, query all available RTSP streams from the Protect bootstrap API and verify audio codec compatibility by parsing the SDP response for each.
2. Prefer the medium-quality stream for audio-only use -- it typically uses standard AAC-LC (mp4a.40.2) and uses less bandwidth.
3. If using a native pipeline instead of ExoPlayer, use FFmpeg for decoding -- it handles virtually every audio codec. The `media_kit` Flutter package wraps FFmpeg/libmpv and has broader codec support.
4. Log the SDP response during connection setup. This is your first debugging artifact when audio doesn't work.
5. Test with every camera model the user might have. Unifi G3, G4, G5 cameras may use different audio encoders.

**Warning signs:**
- Audio works on Camera A but not Camera B.
- Switching stream quality (high/medium/low) breaks audio.
- ExoPlayer logs show "No decoder found" or track selection excludes the audio track.
- Works in VLC but not in your app (VLC supports nearly every codec).

**Phase to address:**
Phase 2 (RTSP Streaming). Codec validation must be part of the camera setup flow, not discovered in production.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Audio pipeline in Dart via MethodChannel | Faster initial development, cross-platform | Latency, jank, memory copies, impossible to optimize | Never for continuous audio streaming |
| Hardcoded RTSP URLs instead of API discovery | Skip Protect API integration | Breaks on IP change, firmware update, or camera swap | Early prototype only (Phase 1 spike), must replace in Phase 2 |
| Single-process foreground service | Simpler architecture | OEM killers more likely to terminate the whole process | Never for overnight reliability |
| Polling-only for smart detection | Simpler than WebSocket binary parsing | 5-10 second delay on cry detection, higher battery/network usage | Acceptable as fallback, not as primary |
| Using `player.stop()` instead of `player.release()` on reconnect | Faster reconnection (no reinitialization) | Memory leak accumulation over hours | Never for long-running streams |
| Skipping OEM battery optimization guidance | Cleaner onboarding UX | App killed overnight on Samsung/Xiaomi devices | Never -- must guide user through this |

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| Unifi Protect Auth | Using only cookie-based auth; breaks on firmware updates | Support both cookie auth and API key (`X-API-KEY`) header; detect and fall back |
| Unifi Protect RTSP | Requesting the high-quality stream for audio-only use | Use medium or low quality stream; audio codec is the same but bandwidth/CPU is much lower |
| Unifi Protect Events | Treating the events list endpoint as real-time | Use `lastMotion`/`lastSmartDetect` from bootstrap for fast detection; events list is slow |
| ExoPlayer RTSP | Relying on UDP transport on WiFi | Force RTP-over-RTSP (TCP interleaved) from the start; UDP is unreliable on consumer WiFi |
| Flutter audio_service | Not declaring `foregroundServiceType` in manifest | Must declare `mediaPlayback` type and permission for Android 14+ or app crashes |
| Android WakeLock | Acquiring FULL wake lock (keeps screen on, drains battery) | Use PARTIAL wake lock only; screen should be off on the nightstand |

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Decoding video track from RTSP even when only audio is needed | High CPU, hot phone, battery drain overnight | Disable video track in ExoPlayer track selection, or use audio-only SDP negotiation | Immediately -- video decode is 10x the CPU of audio |
| Allocating new byte arrays per audio callback | GC pressure, periodic audio glitches every 500ms-2s | Pre-allocate buffers, reuse with ring buffer pattern | After 1-2 hours as heap fragments |
| Logging every audio frame in debug builds | Logcat buffer fills, I/O thread contention causes underruns | Sample logging (1 in 1000 frames) or level-triggered logging only | Within minutes of starting |
| Unthrottled reconnection attempts | Network storm, 429 from NVR auth endpoint, WiFi congestion | Exponential backoff with jitter, max 30s between attempts | On first real network interruption |

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| Storing Protect credentials in SharedPreferences in plaintext | Any app with root or backup access can read credentials | Use Android Keystore via `flutter_secure_storage`; encrypt at rest |
| Logging RTSP URLs with credentials in query params | Credentials in logcat, crash reports, bug report files | Strip credentials before logging; use a sanitized URL format |
| Hardcoding Protect console IP without certificate validation | MITM on local network can intercept audio stream | Accept self-signed certs explicitly (Protect uses self-signed) but pin the certificate on first connection |
| Not rate-limiting auth retries | Account lockout on the Protect console after repeated 401s | Max 3 auth attempts, then require user re-entry of credentials |

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| No visual indicator that audio is actively streaming | Parent can't tell if the monitor is working or silently dead | Persistent audio level meters that show real-time room noise; if meters are flat for 60s, show warning |
| Generic "connection failed" error | Parent doesn't know if it's WiFi, camera, or NVR issue | Specific errors: "Camera X offline", "WiFi disconnected", "NVR not reachable" with suggested action |
| Requiring manual reconnection after stream drop | Parent must wake up, unlock phone, tap reconnect | Fully automatic reconnection with backoff; only notify if reconnection fails 5+ times |
| Battery optimization dialog with no explanation | User dismisses it, app dies at 2am | Explain in plain language: "This app needs to stay awake all night to listen for your baby. Please allow it to run in the background." Show during setup, not randomly |
| Volume sliders without audio preview during setup | Parent can't calibrate volume before going to sleep | Play audio during camera setup so volume can be adjusted with real sound |

## "Looks Done But Isn't" Checklist

- [ ] **Foreground Service:** Works on Pixel but not tested on Samsung/Xiaomi with their battery optimizers -- test on at least 2 OEMs
- [ ] **RTSP Reconnection:** Reconnects after WiFi toggle but not tested after 4+ hours of idle -- test with overnight timer that kills WiFi at 3am
- [ ] **Audio Mixing:** Sounds fine with two identical test streams but not tested with real cameras that have different sample rates -- test with actual Unifi hardware
- [ ] **Memory Stability:** No leaks in 30-minute test but not validated over 8 hours with reconnection cycles -- run overnight with memory profiling
- [ ] **Cry Detection:** Events arrive in testing but not tested with WebSocket disconnection and reconnection -- kill the WebSocket mid-stream and verify recovery
- [ ] **Battery Usage:** App runs overnight but drains 60% battery because video track was being decoded -- verify CPU usage is under 5% steady state
- [ ] **Auth Token:** Login works but not tested with token expiration after 12+ hours -- verify re-auth happens transparently
- [ ] **Notification:** Foreground notification shows but doesn't update with stream status -- verify it reflects actual state (streaming/reconnecting/error)

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| OS killed the service | LOW | Automatic: WorkManager watchdog restarts service within 15 minutes; Manual: user reopens app |
| RTSP stream dropped | LOW | Automatic: exponential backoff reconnection; no user action needed unless it fails 5+ times |
| Memory leak OOM crash | MEDIUM | Automatic: Android restarts the foreground service after OOM; Preventive: periodic pipeline restart every 4 hours |
| Protect API auth broke after firmware update | HIGH | Ship app update with new auth method; provide user workaround: manually enter RTSP URLs as fallback bypass |
| WebSocket binary protocol changed | MEDIUM | Automatic fallback to HTTP polling for cry detection; update binary parser in next app release |
| Audio mixing artifacts | MEDIUM | Switch to single-stream mode (one camera at a time) as degraded fallback; fix mixing in next release |
| Wrong foreground service type on Android 14+ | LOW | Fix manifest and ship update; app will crash on launch until fixed so it's urgent |

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| OS killing foreground service | Phase 1 (Foundation) | Run overnight on Samsung + Pixel; verify service alive after 8 hours |
| RTSP stream silent drop | Phase 2 (Streaming) | Simulate network interruption via WiFi toggle; verify auto-reconnect within 30s |
| Protect API breaking changes | Phase 2 (Unifi Integration) | Abstract behind interface; test both auth methods; log raw API responses |
| Audio mixing artifacts | Phase 2-3 (Audio Pipeline) | Listen to mixed output for 30 minutes; check for clicks/pops; verify with headphones |
| Platform channel bottleneck | Phase 1 (Architecture) | Decision: native audio pipeline, Dart for UI only; validate with profiler |
| Memory leaks over time | Phase 3 (Hardening) | 8-hour memory profile with periodic reconnections; verify RSS stays flat |
| WebSocket binary protocol fragility | Phase 3 (Smart Detection) | Implement dual-mode (WebSocket + polling fallback); test with simulated WebSocket failure |
| Codec negotiation failure | Phase 2 (Streaming) | Test all available stream qualities; log SDP responses; verify with multiple camera models |

## Sources

- [Android Doze and Standby (official)](https://developer.android.com/training/monitoring-device-state/doze-standby)
- [Don't Kill My App - Google](https://dontkillmyapp.com/google)
- [Don't Kill My App - Samsung](https://dontkillmyapp.com/samsung)
- [Don't Kill My App - Xiaomi](https://dontkillmyapp.com/xiaomi)
- [Android Foreground Service Types (Android 14)](https://developer.android.com/about/versions/14/changes/fgs-types-required)
- [Android 15 Foreground Service Changes](https://developer.android.com/about/versions/15/changes/foreground-service-types)
- [ExoPlayer RTSP documentation](https://developer.android.com/media/media3/exoplayer/rtsp)
- [ExoPlayer RTSP session timeout (GitHub #662)](https://github.com/androidx/media/issues/662)
- [ExoPlayer RTSP audio codec support (GitHub #977)](https://github.com/androidx/media/issues/977)
- [hjdhjd/unifi-protect (reverse-engineered API)](https://github.com/hjdhjd/unifi-protect)
- [Unifi Protect auth breaking changes (HA #148886)](https://github.com/home-assistant/core/issues/148886)
- [Flutter Platform Channel performance (Flutter blog)](https://medium.com/flutter/improving-platform-channel-performance-in-flutter-e5b4e5df04af)
- [just_audio memory leak (GitHub #1201)](https://github.com/ryanheise/just_audio/issues/1201)
- [Flutter audio_service package](https://pub.dev/packages/audio_service)
- [Android AAudio documentation](https://developer.android.com/ndk/guides/audio/aaudio/aaudio)
- [Android audio latency contributors](https://source.android.com/docs/core/audio/latency/contrib)
- [Unifi Protect webhooks (official)](https://help.ui.com/hc/en-us/articles/25478744592023-Send-UniFi-Protect-Alerts-to-Web-Services-using-Webhooks)
- [ExoPlayer battery consumption guide](https://developer.android.com/media/media3/exoplayer/battery-consumption)

---
*Pitfalls research for: RTSP audio baby monitor (Flutter/Android, Unifi Protect)*
*Researched: 2026-04-01*
