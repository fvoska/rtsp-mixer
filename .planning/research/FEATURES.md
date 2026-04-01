# Feature Research

**Domain:** Audio baby monitor with RTSP streaming and Unifi Protect integration
**Researched:** 2026-04-01
**Confidence:** HIGH (well-defined niche app with clear prior art from baby monitor market and audio streaming patterns)

## Feature Landscape

### Table Stakes (Users Expect These)

Features the parent (the sole user) will consider the app broken without.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Dual RTSP audio streaming | Core value prop -- listen to 2 rooms at once | HIGH | Must decode audio-only from RTSP, no video. ExoPlayer or platform-native RTSP client needed. This is the hardest table-stakes feature. |
| Per-camera volume control | Parent needs to balance volume between rooms (newborn louder, toddler quieter) | LOW | Two sliders mixing into single audio output. Standard audio mixing. |
| Foreground service with persistent notification | Android kills background apps; overnight reliability requires this | MEDIUM | Must use `FOREGROUND_SERVICE_MEDIA_PLAYBACK` type on Android 14+. Notification shows "listening" status. |
| Screen-off operation | Phone sits on nightstand charging. Screen must be off. | MEDIUM | Requires partial wake lock for CPU + audio focus management. Audio playback services get system-managed wake locks, but RTSP network I/O needs explicit wake lock. |
| Auto-reconnect on stream drop | WiFi blips, camera reboots, Protect updates -- stream WILL drop overnight | HIGH | RTSP has no built-in reconnect. Must implement: detect drop (TCP timeout, RTCP loss, decode errors), exponential backoff retry (1s, 2s, 4s, max 30s), re-authenticate if needed, resume audio seamlessly. Most RTSP apps fail here. |
| Unifi Protect authentication | Need to reach cameras; Protect API requires auth | MEDIUM | Login to Protect controller, get bootstrap JSON, extract camera list and RTSP URLs. Credentials must persist securely (Android Keystore). |
| Camera discovery and selection | User should pick cameras from a list, not type RTSP URLs | LOW | Protect API bootstrap endpoint returns all cameras with names, IDs, and stream channels. Display list, let user pick 2. |
| Credential persistence and auto-connect | App must reconnect automatically when opened or after phone restart | LOW | Store encrypted credentials, auto-authenticate on launch, resume last camera selection. |
| Connection status indicator | Parent must know at a glance if audio is live or dropped | LOW | Simple status per camera: connecting, live, reconnecting, error. Color-coded dot or icon. |

### Differentiators (Competitive Advantage)

Features that make this app better than "just use VLC" or the Unifi app.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Cry detection via Unifi Protect AI | Auto-alert when baby cries even if audio is muted or phone volume is low. Leverages existing Unifi AI -- no custom ML needed. | MEDIUM | Subscribe to Protect realtime events websocket (`wss://nvr/proxy/protect/ws/updates`). Filter for smart detection events with type "babyCrying". Fire local notification + optional alarm sound. |
| Per-camera listening mode (continuous / cry-triggered / off) | Continuous for newborn, cry-triggered for toddler who sleeps well. Saves battery by not streaming when not needed. | MEDIUM | "Off" = no stream. "Continuous" = always streaming. "Cry-triggered" = stream starts on Protect cry event, stops after configurable quiet period. Requires websocket subscription + stream lifecycle management. |
| Audio level meters | Visual feedback that audio is actually coming through. Parent glances at phone and sees activity bars moving = trust that monitoring is working. | LOW | Compute RMS/peak from decoded PCM samples. Display as simple bar per camera. Critical for "is it still working?" confidence. |
| Push notification on cry detection | Even if app is in background, parent gets alerted. Works alongside the foreground service. | LOW | Local notification triggered by Protect websocket event. No cloud push infrastructure needed since app is already running as foreground service. |
| Health monitoring and overnight status | Morning summary: "Monitored 8h 12m, 2 reconnections, 3 cry events at 1:15am, 3:42am, 5:01am" | LOW | Log events to local DB. Display summary screen. Builds trust that monitoring was reliable all night. |
| WiFi lock (high-performance WiFi) | Prevent Android from throttling WiFi to save battery, which would kill RTSP streams | LOW | Acquire `WifiManager.WifiLock` with `WIFI_MODE_FULL_HIGH_PERF`. Essential for reliable overnight streaming but often overlooked. |
| Stream health heartbeat | Background watchdog that verifies audio data is actually flowing, not just that the TCP connection is open | MEDIUM | Monitor decoded audio frame rate. If no frames for N seconds, force reconnect. Catches "zombie stream" scenarios where TCP stays open but camera stops sending data. |

### Anti-Features (Commonly Requested, Often Problematic)

Features to deliberately NOT build.

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Video display | "Why not show the camera feed too?" | Massive battery drain overnight. Video decoding is 10-50x more CPU than audio-only. Defeats the core value of reliable overnight operation. Phone screen would need to stay on. | Audio-only with level meters provides monitoring confidence without battery drain. Open Unifi app when you actually need to look. |
| Custom cry detection ML | "What if Unifi AI misses cries?" | Requires on-device ML model, continuous audio analysis, significant battery drain, and ongoing model tuning. False positives are worse than false negatives (parent wakes up for nothing). | Use Unifi's built-in AI which runs on the camera/NVR, not the phone. Zero phone battery cost. Already trained and tuned. |
| Remote/cloud access | "Listen from outside the house" | Requires TURN/relay server, authentication infrastructure, NAT traversal, latency issues. Massively increases complexity. | LAN-only. If you're not home, you're not the one monitoring. Baby monitor is a nightstand device. |
| Two-way audio / talk-back | "Talk to the baby through the camera" | Requires audio capture, encoding, RTSP back-channel or Protect API audio push, echo cancellation. Complex and rarely used -- parent walks to the room instead. | Not implemented. Walk to the room. |
| Support for 3+ cameras | "What about families with 3+ kids?" | Complicates UI (mixing 3+ streams), increases battery drain linearly, and this app is built for a specific 2-camera household. | Exactly 2 cameras. Keep it simple. If needed later, it's an incremental change. |
| EQ / noise filtering / audio processing | "Filter out white noise machines, enhance cry sounds" | Audio DSP adds latency, CPU usage, and complexity. White noise machines are constant-level and don't interfere with cry detection (Unifi handles that). Volume control is sufficient. | Per-camera volume control. Let the Unifi AI handle cry vs noise discrimination. |
| Sleep/wake scheduling | "Auto-start monitoring at 7pm, stop at 7am" | Over-engineering. Parent opens app at bedtime, closes in morning. A 2-tap interaction doesn't need automation. | Manual start/stop. App remembers last camera selection for quick restart. |
| Smartwatch companion app | "See status on Apple Watch / WearOS" | Separate app, separate platform, separate maintenance. Notification on phone is sufficient. | Push notifications already reach the watch via standard Android notification bridging. |

## Feature Dependencies

```
[Unifi Protect Auth]
    |
    +---> [Camera Discovery] ---> [Camera Selection UI]
    |                                    |
    |                                    v
    |                          [RTSP Audio Streaming (x2)]
    |                                    |
    |                          +---------+---------+
    |                          |                   |
    |                          v                   v
    |                  [Volume Mixing]    [Audio Level Meters]
    |                          |
    |                          v
    |                  [Foreground Service]
    |                          |
    |                  +-------+-------+
    |                  |               |
    |                  v               v
    |          [Wake Lock +      [Auto-Reconnect]
    |           WiFi Lock]             |
    |                                  v
    |                          [Stream Health Monitor]
    |
    +---> [Protect Websocket Events]
                    |
                    v
            [Cry Detection Events]
                    |
            +-------+-------+
            |               |
            v               v
    [Push Notification] [Cry-Triggered Mode]
                              |
                              v
                    [Stream Lifecycle Mgmt]
```

### Dependency Notes

- **RTSP Audio Streaming requires Unifi Protect Auth + Camera Discovery:** Cannot connect to streams without discovering RTSP URLs from the Protect API.
- **Volume Mixing requires RTSP Audio Streaming:** Cannot mix what you're not decoding.
- **Audio Level Meters require RTSP Audio Streaming:** Need decoded PCM data to compute levels.
- **Auto-Reconnect requires Foreground Service:** Reconnect logic must run even when screen is off; foreground service keeps the process alive.
- **Cry Detection requires Protect Websocket Events:** Smart detection events arrive via the realtime websocket, independent of RTSP streams.
- **Cry-Triggered Mode requires both Cry Detection and Stream Lifecycle Management:** Must start/stop RTSP streams in response to detection events.
- **Stream Health Monitor enhances Auto-Reconnect:** Detects zombie streams that auto-reconnect's TCP-level checks would miss.

## MVP Definition

### Launch With (v1)

Minimum viable product -- enough to replace VLC on the nightstand.

- [ ] Unifi Protect authentication (console IP + credentials) -- gate to everything
- [ ] Camera discovery and 2-camera selection -- avoid manual RTSP URL entry
- [ ] Dual RTSP audio-only streaming -- the core feature
- [ ] Per-camera volume sliders -- basic mixing control
- [ ] Android foreground service with persistent notification -- overnight survival
- [ ] Partial wake lock + WiFi lock -- prevent OS from throttling
- [ ] Auto-reconnect with exponential backoff -- handle overnight disruptions
- [ ] Connection status indicators -- parent trust that it's working

### Add After Validation (v1.x)

Features to add once core streaming is proven reliable overnight.

- [ ] Audio level meters -- after streaming works, add visual feedback
- [ ] Protect websocket event subscription -- foundation for cry features
- [ ] Cry detection notifications -- alert parent on Unifi AI baby cry events
- [ ] Per-camera mode (continuous / cry-triggered / off) -- power-saving flexibility
- [ ] Stream health heartbeat watchdog -- catch zombie streams
- [ ] Overnight health summary -- morning report of monitoring reliability

### Future Consideration (v2+)

Features to defer until the app is battle-tested.

- [ ] Web companion (Flutter web target) -- nice-to-have, not critical
- [ ] Multiple Protect console support -- for users with complex setups
- [ ] Configurable reconnect parameters -- expose backoff settings to user
- [ ] Audio recording / event log with playback -- record cry events for review

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| Dual RTSP audio streaming | HIGH | HIGH | P1 |
| Per-camera volume control | HIGH | LOW | P1 |
| Foreground service + wake/WiFi locks | HIGH | MEDIUM | P1 |
| Auto-reconnect | HIGH | HIGH | P1 |
| Protect auth + camera discovery | HIGH | MEDIUM | P1 |
| Connection status indicators | HIGH | LOW | P1 |
| Credential persistence + auto-connect | MEDIUM | LOW | P1 |
| Audio level meters | MEDIUM | LOW | P2 |
| Cry detection via Protect events | HIGH | MEDIUM | P2 |
| Push notification on cry | HIGH | LOW | P2 |
| Per-camera listening mode | MEDIUM | MEDIUM | P2 |
| Stream health heartbeat | MEDIUM | MEDIUM | P2 |
| WiFi lock (high-perf) | MEDIUM | LOW | P1 |
| Overnight health summary | LOW | LOW | P3 |

**Priority key:**
- P1: Must have for launch -- app is broken without these
- P2: Should have, add once core streaming is reliable
- P3: Nice to have, future consideration

## Competitor Feature Analysis

| Feature | Unifi Protect App | VLC (RTSP) | Dedicated Baby Monitor Apps (Nanit, Lollipop) | Our Approach |
|---------|-------------------|------------|-----------------------------------------------|--------------|
| Audio monitoring | Yes (with video, screen must be on) | Yes (single stream, unreliable overnight) | Yes (proprietary cameras only) | Audio-only, dual stream, screen off |
| Multi-camera audio | No (one camera at a time) | No (one stream per instance) | Some (with their own cameras) | Mix 2 cameras simultaneously |
| Cry detection | Yes (in-app alerts) | No | Yes (custom ML, cloud-dependent) | Leverage Unifi AI, no extra ML |
| Background operation | Poor (requires screen on) | Poor (drops overnight) | Good (purpose-built) | Foreground service, wake lock, WiFi lock |
| Auto-reconnect | App-level only | None | Good (proprietary protocol) | Custom RTSP reconnect with health monitoring |
| Volume mixing | No | Single stream volume only | Limited | Per-camera independent volume sliders |
| VOX / cry-triggered mode | No | No | Yes (with sensitivity settings) | Via Unifi Protect smart detection events |
| Audio level visualization | No | Basic (with video) | Some | Per-camera level meters, no video overhead |

## Sources

- [Stormotion - Baby Monitoring App Development Guide](https://stormotion.io/blog/baby-monitoring-app-development/)
- [Ubiquiti - AI Detections and Facial Recognition](https://help.ui.com/hc/en-us/articles/360058867233-Advanced-AI-Features-in-UniFi-Protect)
- [Ubiquiti - Alarm Manager](https://help.ui.com/hc/en-us/articles/27721287753239-UniFi-Alarm-Manager-Customize-Alerts-Integrations-and-Automations-Across-UniFi)
- [Home Assistant - UniFi Protect Integration](https://www.home-assistant.io/integrations/unifiprotect/)
- [hjdhjd/unifi-protect - GitHub](https://github.com/hjdhjd/unifi-protect) -- open source Protect API implementation, realtime websocket protocol
- [Android Developers - Foreground Service Types](https://developer.android.com/develop/background-work/services/fgs/service-types)
- [Android Developers - Doze and App Standby](https://developer.android.com/training/monitoring-device-state/doze-standby)
- [Android Developers - Keep Device Awake](https://developer.android.com/develop/background-work/background-tasks/awake)
- [Spreaker - Fighting with Doze and Audio Streaming](https://medium.com/spreaker-developers/fighting-with-doze-app-standby-and-audio-streaming-234249197241)
- [Android Developers - RTSP with ExoPlayer](https://developer.android.com/media/media3/exoplayer/rtsp)
- [Lollipop - Smart Detection (Cry, Motion, Noise)](https://support.lollipop.camera/hc/en-us/articles/4410890181273-Smart-Detection-Cry-Motion-Noise)
- [eufy - VOX on Baby Monitor](https://www.eufy.com/blogs/baby/what-is-vox-on-baby-monitor)
- [Reolink - Baby Monitor Apps](https://reolink.com/blog/baby-monitor-apps-for-iphone-ipad-android/)
- [Nanit - Customizing Notification Settings](https://support.nanit.com/hc/en-us/articles/235674188-Customizing-Notification-Settings)

---
*Feature research for: RTSP Audio Baby Monitor with Unifi Protect Integration*
*Researched: 2026-04-01*
