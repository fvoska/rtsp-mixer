# Phase 4: Reliability + Overnight Monitoring - Research

**Researched:** 2026-04-23
**Domain:** Android foreground reliability, Flutter/libmpv RTSP error recovery, local wake-up notifications
**Confidence:** HIGH overall — all locked decisions map to verified APIs; two risks require on-device validation.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Auto-Reconnect (RELY-01)**
- **D-01** — Exponential backoff capped at 30s (1s → 2s → 4s → 8s → 16s → 30s → 30s …) with ±20% jitter to avoid thundering-herd on simultaneous drops.
- **D-02** — Retry forever. Never give up on its own. This is emotionally load-bearing — the parent must trust it's still trying.
- **D-03** — Reconnect triggered by ANY of: (a) `Player.stream.error`/`completed` events, (b) zombie detector firing, (c) WiFi reconnect via `connectivity_plus`. Researcher MUST enumerate ALL realistic RTSP interruption modes and confirm each path reaches a reconnect attempt.
- **D-04** — Per-camera one-shot local push notification fires when a camera has been in non-`playing` state for 5 continuous minutes. Resets on recovery. One-shot per outage cycle.

**Zombie Stream Detection (RELY-03)**
- **D-05** — 60-second threshold.
- **D-06** — Four signals combined: (1) `audio-pts` stall, (2) `Player.stream.buffering` stuck `true` for 60s, (3) `audio-bitrate` sustained 0 alongside PTS stall, (4) no new `Player.stream.audioParams` events for 60s. Researcher/planner pick OR vs quorum to minimize false positives.
- **D-07** — On zombie detection, force reconnect silently. Status → `reconnecting`. Log to health stream.
- **D-08** — Threshold hardcoded (not in `AppSettings`).

**Connection Status UI (RELY-02)**
- **D-09** — Expand `CameraConnectionStatus` enum to: `idle | connecting | playing | reconnecting | error`.
- **D-10** — Amber tint + spinner on card header for `reconnecting`.
- **D-11** — Status only — no attempt count, no countdown on the card.
- **D-12** — No global indicator; per-card only.

**Overnight Health Summary (MNTR-01)**
- **D-13** — Session-scoped counters (`startMonitoring` → `stopMonitoring`).
- **D-14** — In-memory only for v1.
- **D-15** — Event stream: `stream_started`, `stream_error`, `reconnect_attempt`, `reconnect_success`, `zombie_detected`, `wifi_dropped`, `wifi_reconnected`, `alert_fired`, `monitoring_stopped`.
- **D-16** — App bar icon on monitoring screen opens a summary screen.
- **D-17** — 1,000-event in-memory cap.

### Claude's Discretion
- Exact AsyncNotifier / state machine shape for the reconnect loop.
- Whether zombie detection runs on the existing 500ms `_levelPollTimer` or a dedicated timer.
- `flutter_local_notifications` channel/category setup (priority, sound, importance).
- `connectivity_plus` subscription point; debounce strategy.
- Quorum vs OR logic across the four zombie signals.
- MNTR-01 summary screen layout, copy, typography.

### Deferred Ideas (OUT OF SCOPE)
- User-tunable zombie threshold.
- Cross-session health summary persistence.
- Global app-bar reconnect indicator.
- Attempt-count / countdown on card.
- Alert escalation (louder at 15min).
- Coalesced multi-camera alert.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| RELY-01 | Auto-reconnect dropped streams with exponential backoff | Sections 1, 2, 5 — interruption taxonomy, `player.open()` reuse pattern, state machine design |
| RELY-02 | Per-camera connection status UI | Sections 5, 10 — status enum expansion, CameraAudioCard integration points |
| RELY-03 | Zombie stream detection + forced reconnect | Sections 2, 5 — mpv property semantics, 4-signal fusion logic |
| MNTR-01 | Overnight health summary | Section 6 — event stream design, memory footprint, render strategy |
</phase_requirements>

## Summary

Phase 4 wraps the existing `AudioPlayerNotifier` (686 lines) with a reconnect supervisor, a zombie watchdog, a WiFi-change listener, and a per-session event recorder. All four features live on or beside the existing notifier — no new state management paradigm. Two Flutter packages are added: `connectivity_plus ^7.1.1` for WiFi drop/reconnect detection, and `flutter_local_notifications ^19.0.0` (or `^21.0.0` after a Dart SDK bump) for the 5-minute one-shot wake-up alert. No backend, no ML, no new audio pipeline changes.

The highest-risk finding is that **Android Doze mode continues to apply even inside an active foreground service** (wake locks, `Timer.periodic` and `AlarmManager` can all be deferred). This is a real concern for overnight reliability, but the existing Phase 3 code already requests battery-optimization exemption via `FlutterForegroundTask.requestIgnoreBatteryOptimization()` plus a partial `WakeLock`, which materially reduces Doze impact. The reconnect loop is mostly driven by player events and connectivity events, not timers, so it is resilient to some Doze deferral. The two timer-dependent pieces — the 5-minute alert clock and the zombie watchdog — need on-device validation to confirm they fire on a quiet phone with the screen off. The plan should include an explicit overnight validation task on a real Android device.

**Primary recommendation:** Add `connectivity_plus: ^7.1.1` and `flutter_local_notifications: ^19.0.0` (pin below 20.x to avoid Dart SDK 3.10 bump), expand `CameraConnectionStatus` with `reconnecting`, add a `_ReconnectSupervisor` helper class alongside `AudioPlayerNotifier` that owns per-camera backoff state and the alert-pending timer, piggyback the zombie watchdog on the existing 500ms `_levelPollTimer` by tracking signal-age counters, and expose the health summary as a separate Riverpod `Notifier<List<HealthEvent>>` that `AudioPlayerNotifier` writes to. All reconnect code paths must be individually wrapped in try/catch per the non-negotiable "streams must never break" convention.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| RTSP reconnect loop / backoff timer | Flutter main isolate (`AudioPlayerNotifier`) | Foreground service isolate (keeps process alive only) | Players live in the main isolate per Phase 3 architecture (`lib/core/services/foreground_service.dart:89-115` — `MonitoringTaskHandler` comment: "Players live in the main isolate — this handler only receives notification actions"). The reconnect state machine must co-locate with the player instances. |
| Zombie watchdog | Flutter main isolate (existing `_levelPollTimer`) | — | The watchdog reads mpv properties (`audio-pts`, `audio-bitrate`) that only the Player owner can access; same place as existing silence-duration tracking. |
| WiFi connectivity listening | Flutter main isolate (Riverpod stream sub) | OS (Android ConnectivityManager) | `connectivity_plus` is a plugin that bridges Android's network callbacks to a Dart `Stream`; subscription has to live where it can dispatch into the notifier. |
| 5-minute alert timer | Flutter main isolate | OS (Android AlarmManager via `flutter_local_notifications` for scheduled fallback) | A plain `Timer(5m)` is simplest; see Pitfall 2 (Doze) for the fallback plan if timer-only proves unreliable. |
| Notification rendering (5-min alert) | OS (Android NotificationManager via plugin) | — | The plugin hands off to the Android framework; we only configure the channel. |
| Health event recording | Flutter main isolate (new Riverpod `Notifier`) | — | Consumers (summary screen, logs) are all UI-thread readers. |
| Foreground service notification text | OS (Android foreground-service framework via `FlutterForegroundTask.updateService`) | Flutter main isolate (builds the text) | Existing pattern in `ForegroundServiceManager.updateNotification` — this phase only extends the text builder to include `reconnecting` status. |

## Standard Stack

### Core (new for this phase)

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `connectivity_plus` | `^7.1.1` | Subscribe to Android WiFi/mobile connectivity changes, fire a reconnect on WiFi re-up | `[VERIFIED: pub.dev]` — 7.1.1 published ~13 days ago (Apr 2026). Maintained by Flutter Community. De facto standard for Flutter connectivity detection. Already referenced in `CLAUDE.md` §Supporting Libraries. |
| `flutter_local_notifications` | `^19.0.0` (pinned to avoid 21.x Dart 3.10 requirement) | Fire the 5-minute one-shot per-camera alert when a camera has been non-`playing` for 5 minutes | `[VERIFIED: pub.dev]` — 21.0.0 is latest but requires Dart SDK 3.10 (project is on `^3.9.2`). 19.x line requires Flutter 3.22 and Dart 3.2+, matches project. Industry standard local notification plugin. |

**Dart SDK note:** `[VERIFIED: pub.dev]` The project's `pubspec.yaml` declares `sdk: ^3.9.2`. `flutter_local_notifications 20.x+` requires Dart SDK 3.10+. Two options:
- **Option A (safe, default):** pin `flutter_local_notifications: ^19.0.0`.
- **Option B (optional):** bump `sdk: ^3.10.0` in `pubspec.yaml` and use `^21.0.0`.
Planner should pick Option A unless there's a specific 20.x/21.x feature needed. Nothing in Phase 4's requirements needs anything past 19.x.

### Supporting (already installed)

| Library | Version (in use) | Purpose | When Used in Phase 4 |
|---------|------------------|---------|----------------------|
| `media_kit` | `^1.2.6` | RTSP player | `Player.open()` is re-called on the same instance to reconnect (verified pattern — see Section 2) |
| `flutter_riverpod` | `^3.3.1` | State management | New `HealthEventsNotifier`; existing `AudioPlayerNotifier` extended |
| `flutter_foreground_task` | `^9.2.2` | Foreground service | Notification text updates extended to include `reconnecting` status |
| `logging` (via `appLog`) | — | Structured logging | Every reconnect event logs via `appLog('RECONNECT', ...)` in addition to appending to the health stream |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `connectivity_plus` | `internet_connection_checker_plus` | `[CITED: pub.dev]` Would give us actual internet-reachability pings, not just link status. Rejected: we need LAN reachability (cameras on local network), internet status is irrelevant. Adding ping-to-camera logic is done directly in our reconnect loop, not via a package. |
| `flutter_local_notifications` | `awesome_notifications` | More features (rich content, custom layouts) we don't need; larger dependency footprint. Stick with the established standard. |
| Direct `Timer(5m)` for alert | `WorkManager` / `AlarmManager` scheduled task | `[CITED: Android docs]` WorkManager is the correct primitive for time-sensitive tasks that must survive Doze, but adds plumbing complexity. `[ASSUMED]` Given the foreground service + battery-opt exemption already established in Phase 3, a plain `Timer(5m)` running in the main isolate is expected to fire. This is the #1 item to verify on-device overnight (see Section 8, Pitfall 2). If it turns out to be unreliable, upgrade to `flutter_local_notifications`' scheduled-notification API with `AndroidScheduleMode.exactAllowWhileIdle`. |
| OR-combining four zombie signals | Quorum (≥2 of 4) | OR triggers reconnect on any single stall; quorum reduces false positives on streams that legitimately go silent for 60+ seconds between signals. See Section 5. **Recommendation: quorum ≥ 2**. |

**Installation:**
```bash
flutter pub add connectivity_plus:^7.1.1
flutter pub add flutter_local_notifications:^19.0.0
```

## Architecture Patterns

### System Architecture Diagram

```
                              Phase 4 Reliability Additions
                              ==============================

         ┌────────────────── Android OS ────────────────────────┐
         │                                                       │
         │  ConnectivityManager ─ callback ─► connectivity_plus  │
         │         │                              Stream         │
         │  NotificationManager ◄─ show ── flutter_local_         │
         │                                    notifications      │
         └────────────┬──────────────────────────────────────────┘
                      │ OS events            ▲ fire alert
                      │ (WiFi on/off)        │
                      │                      │
         ═══════════════════════════════════════════════════════
                   Flutter Main Isolate
         ═══════════════════════════════════════════════════════
                      │                      │
                      ▼                      │
             ┌──────────────────┐            │
             │ Connectivity     │            │
             │   Listener       │            │
             └────────┬─────────┘            │
                      │                      │
                      │  (WiFi reconnected   │
                      │   event)             │
                      ▼                      │
             ┌───────────────────────────────────────────────┐
             │          ReconnectSupervisor                   │
             │  (per-camera: attempt#, nextRetry, alertTimer)│
             │                                                │
             │  triggers from ANY of:                         │
             │   - WiFi reconnected                           │
             │   - Player.stream.error                        │
             │   - Player.stream.completed                    │
             │   - Zombie watchdog fires                      │
             │                                                │
             │  actions:                                      │
             │   - computeBackoff() → Timer(delay) → open()   │
             │   - startAlertTimer(5m) on first non-playing   │
             │   - cancelAlertTimer() on recovery             │
             │   - dedupe (in-flight guard)                   │
             └────────┬──────────────────────────┬────────────┘
                      │                          │
                      │ open/stop/volume          │ append
                      │                          │ event
                      ▼                          ▼
             ┌──────────────────┐   ┌──────────────────────┐
             │ media_kit.Player │   │ HealthEventsNotifier │
             │   (per camera)   │   │   (ring buffer 1000) │
             └────────┬─────────┘   └──────────┬───────────┘
                      │                        │
                      │ stream.error /         │
                      │ completed /            │
                      │ buffering /            │
                      │ audioParams            │
                      ▼                        │
             ┌──────────────────┐              │
             │ ZombieWatchdog   │              │
             │ (on 500ms poll)  │              │
             │  signals:        │              │
             │  - audio-pts age │              │
             │  - buffering-age │              │
             │  - bitrate=0-age │              │
             │  - params-age    │              │
             │                  │              │
             │  quorum ≥ 2 →    │              │
             │  request reconnect               │
             └──────────────────┘              │
                                               │
                                               ▼
                                     ┌──────────────────┐
                                     │  SummaryScreen   │
                                     │ (reads events +  │
                                     │  monitoring state)│
                                     └──────────────────┘
```

Primary flow (happy path):
1. User taps Start → existing code opens 2 Players.
2. `AudioPlayerNotifier` subscribes once to `connectivity_plus.onConnectivityChanged`.
3. `AudioPlayerNotifier` already subscribes to `player.stream.error/completed/buffering/audioParams` — extended to enqueue a reconnect request instead of only logging.
4. `_levelPollTimer` (existing 500ms) extended with zombie signal-age tracking; on quorum, enqueue reconnect.
5. `ReconnectSupervisor.requestReconnect(cameraId, cause)` dedupes overlapping requests, schedules a `Timer` based on backoff state, and on fire calls `player.open(Media(url))` on the SAME Player instance.
6. On first transition to non-`playing`, `ReconnectSupervisor` starts a 5-minute Timer per camera. On transition back to `playing`, cancel the Timer and reset the alert-fired flag.
7. Every transition logs both to `appLog` (existing) AND to `HealthEventsNotifier` (new).

### Recommended File Layout

```
lib/features/monitoring/
├── providers/
│   ├── audio_player_provider.dart      # existing; extended (see Section 10)
│   └── health_events_provider.dart     # NEW — Riverpod Notifier<List<HealthEvent>>
├── models/
│   ├── player_state.dart                # existing; expand CameraConnectionStatus enum
│   └── health_event.dart                # NEW — immutable record { timestamp, cameraId, eventType, detail? }
├── services/
│   ├── reconnect_supervisor.dart        # NEW — per-camera backoff state + alert timer
│   ├── zombie_watchdog.dart             # NEW — signal-age tracking + quorum logic
│   └── connectivity_listener.dart       # NEW — connectivity_plus subscription + debounce
├── screens/
│   ├── monitoring_screen.dart           # existing; add AppBar icon to open summary
│   └── health_summary_screen.dart       # NEW — chronological event list + per-camera counters
└── widgets/
    └── camera_audio_card.dart           # existing; render `reconnecting` amber+spinner

lib/core/services/
├── foreground_service.dart              # existing; extend updateNotification with reconnect status
└── local_notifications.dart             # NEW — 5-min alert channel setup, fire/cancel helpers
```

### Pattern 1: Reuse Player instance across reconnect
**What:** Call `player.open(Media(url))` on an existing Player rather than dispose+recreate.
**When to use:** Every reconnect trigger in Phase 4.
**Why:** Preserves mpv state including `setProperty` values (cache, demuxer-lavf-o, audio-buffer). Avoids dispose race conditions (reported in media_kit issue tracker). Lighter on resources than full teardown.

```dart
// Source: Medium "Building a Fault-Tolerant Live Camera Streaming Player in Flutter (with media_kit)"
// [CITED: https://medium.com/@pranav.tech06/building-a-fault-tolerant-live-camera-streaming-player-in-flutter-with-media-kit-28dcc0667b7a]

Future<void> _openWithRetry(Player player, String url) async {
  try {
    await player.stop();                      // ensure stopped before reopen
    await Future.delayed(const Duration(milliseconds: 200));
    await player.open(Media(url));            // SAME instance, new Media
  } catch (e) {
    appLog('RECONNECT', 'open() failed: $e');
    rethrow;  // supervisor catches and schedules next attempt
  }
}
```

**⚠️ [ASSUMED]** Whether mpv properties set via `NativePlayer.setProperty` (cache=yes, demuxer-max-bytes, demuxer-lavf-o=rtsp_transport=tcp, audio-buffer) survive a `player.open()` call on the same instance is NOT documented. Plan should include an explicit verification task: after first reconnect, `getProperty('cache')` and confirm it's still `'yes'`. If properties reset, supervisor must re-apply them after every successful open.

### Pattern 2: Exponential backoff with jitter
**What:** Compute delay as `min(30s, base * 2^attempt)` and add `±20%` noise.
**When to use:** After every failed reconnect attempt.

```dart
Duration computeBackoff(int attempt) {
  // D-01: 1, 2, 4, 8, 16, 30, 30, 30 ...
  final base = 1 << attempt.clamp(0, 5);         // 1, 2, 4, 8, 16, 32
  final capped = base > 30 ? 30 : base;          // cap at 30s
  final jitter = 1.0 + (Random().nextDouble() - 0.5) * 0.4; // ±20%
  final ms = (capped * 1000 * jitter).round();
  return Duration(milliseconds: ms);
}
```

### Pattern 3: Dedupe overlapping reconnect requests
**What:** An in-flight guard per camera ID.
**When to use:** Multiple triggers (WiFi + player error + zombie) can fire within the same 100ms window; without dedup, we'd tear down a Player mid-reconnect.

```dart
final Map<String, bool> _reconnectInFlight = {};

Future<void> requestReconnect(String cameraId, String cause) async {
  if (_reconnectInFlight[cameraId] == true) {
    appLog('RECONNECT', '$cameraId: suppressed duplicate request ($cause)');
    return;
  }
  _reconnectInFlight[cameraId] = true;
  try {
    await _performReconnect(cameraId);
  } finally {
    _reconnectInFlight[cameraId] = false;
  }
}
```

### Pattern 4: Defensive recurring timer
**What:** Every iteration of the backoff timer must individually try/catch.
**When to use:** Non-negotiable for ALL new async work per `CLAUDE.md` §Conventions.

```dart
void _scheduleRetry(String cameraId, Duration delay) {
  _retryTimers[cameraId]?.cancel();
  _retryTimers[cameraId] = Timer(delay, () async {
    try {
      await _attemptReconnect(cameraId);
    } catch (e, st) {
      appLog('RECONNECT', '$cameraId: retry crashed: $e\n$st');
      // IMPORTANT: schedule the NEXT retry even on crash — retry forever (D-02)
      try {
        final next = computeBackoff(_attempts[cameraId] ?? 0);
        _scheduleRetry(cameraId, next);
      } catch (_) {
        // double-catch: if even scheduling fails, we log and leak the loop
        // but the player stream.error listener will kick the supervisor again
        appLog('RECONNECT', '$cameraId: scheduling itself failed');
      }
    }
  });
}
```

### Anti-Patterns to Avoid

- **Disposing Player on every reconnect** — slower, leaks VideoController references, defeats the point of keeping a stable instance. Only `stop()` + `open()`.
- **Synchronous retry loops (`while (!connected)`)** — blocks the event loop; would freeze the UI. All retries are timer-scheduled.
- **Unhandled futures** — every `await` in the reconnect supervisor must be inside try/catch. A single uncaught exception in a timer callback will tear down the whole stream listening setup.
- **Retrying in the OS foreground-service isolate** — the comment in `foreground_service.dart:84-88` is explicit: "Players live in the main isolate — this handler only receives notification actions." Do not try to run reconnect from the service isolate.
- **Skipping backoff reset on success** — after a successful open, set `_attempts[cameraId] = 0` or the next drop starts from the last-used delay instead of 1s.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| WiFi drop detection | Custom `NetworkInterface.list()` polling | `connectivity_plus` | Reads Android `ConnectivityManager.NetworkCallback` which fires on OS events, not polled. Polling would miss short drops. |
| Local notifications | Custom `MethodChannel` to Android `NotificationManagerCompat` | `flutter_local_notifications` | Plugin handles channels, Android 13+ permission flow, Android 14 FSI restrictions, cross-device quirks. ~500 LOC we don't have to write or maintain. |
| Exponential backoff | Roll from scratch | Roll from scratch | Actually DO hand-roll this — it's 8 lines (see Pattern 2). Pulling `retry` package is overkill. |
| Ring buffer for events | `List.add` + manual trim | `ListQueue<HealthEvent>` (already used in `app_logger.dart:27`) | Same pattern as the existing AppLogger. Keeps implementation symmetric. |

**Key insight:** The two new dependencies cover OS-boundary integration (network callbacks + notification manager). Everything else is pure Dart and belongs in-repo — no library needed for backoff math, dedup, or state machine logic.

## Runtime State Inventory

This is not a rename/refactor phase — primarily additive feature work. No existing runtime state is being renamed. One minor item:

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | None — phase is session-scoped in-memory (D-14). | None. |
| Live service config | None. | None. |
| OS-registered state | Android notification channels (new): `baby_monitor_alert` for 5-min alerts. Must be created before first notification fires; safe to call `createNotificationChannel` idempotently at app start. | Plan step: register channel during app init alongside existing `ForegroundServiceManager.init()`. |
| Secrets/env vars | None. | None. |
| Build artifacts | `flutter_local_notifications` and `connectivity_plus` add native Android code; will trigger Gradle rebuild. No stale artifacts after `flutter clean`. | None — standard `flutter pub get` + rebuild. |

**Nothing else in these categories** — verified by reading `CLAUDE.md` §Conventions, `.planning/STATE.md` §Accumulated Context, and the existing code files.

## Section 1 — RTSP Interruption Mode Taxonomy (D-03 enumeration)

Every mode below must reach a reconnect attempt via at least one of the three triggers (player event, zombie watchdog, WiFi reconnect). **Coverage column** marks which trigger catches it.

| # | Interruption Mode | Player Signal | Typical Downtime | connectivity_plus fires? | Right Response | Coverage |
|---|---|---|---|---|---|---|
| 1 | Unifi Protect (UDM Pro NVR) software update | Stream drops; `player.stream.error` likely fires once TCP closes; then `open()` will fail until NVR is back. | 1–5 min | No (WiFi still up) | Exponential backoff — retry forever until NVR responds. | **T1** (player.error) + T2 (zombie if TCP lingers half-open) |
| 2 | UDM Pro firmware update (router itself) | TCP dies; player stream.error. **LAN disappears entirely** — WiFi stays connected to AP but gateway is gone. | 2–10 min | **Ambiguous** — AP may stay up. Android may or may not fire a connectivity change (depends on whether default route is still reachable). [ASSUMED] | Backoff. Reconnect attempts will fail (name resolution / TCP fail) until UDM reboots. | **T1** (player.error) |
| 3 | Camera firmware update | Per-camera RTSP drop, the other camera keeps playing. `player.stream.error` on just that one. | 2–5 min | No | Backoff that ONE camera. Leave the other alone. | **T1** |
| 4 | Camera power cycle (PoE reboot) | Same as #3 — per-camera drop. | 30s–2min | No | Backoff. | **T1** |
| 5 | WiFi access-point reboot / firmware update | Both cameras drop simultaneously. Android WiFi goes DOWN then UP. | 1–3 min | **YES** — connectivity state goes `[wifi]` → `[none]` → `[wifi]` | On `none` → mark all cameras `reconnecting` (but don't tear down — network is gone, open() will fail). On `wifi` return → trigger immediate reconnect attempt (bypass backoff for this trigger path, per D-03's WiFi-reconnect-triggered retry semantics). | **T3** (primary) + T1 (secondary, player.error fires when TCP dies) |
| 6 | WiFi router reboot (different box from AP) | LAN may stay up if AP is separate, then cameras still reachable; OR it all drops. | 1–3 min | Variable | Same as #5 — on `none` hold, on reconnect attempt immediately. | **T3** + **T1** |
| 7 | Ethernet/LAN cable disconnect (somewhere in LAN) | Cameras unreachable; player.stream.error. Android WiFi stays "connected" (to AP). | Variable — could be minutes | **No** — WiFi link is up, only routing is broken | Backoff, forever. Zombie may fire if player doesn't emit error (TCP half-open). | **T1** + **T2** (zombie) |
| 8 | Phone WiFi drop (out of range, temporary) | Player.stream.error will follow as TCP timeouts hit; may take 30–60s before error fires. | 10s–1min | **YES** — `[wifi]` → `[none]` (or `[mobile]`). | Mark cameras `reconnecting` when `none`. On WiFi back, reconnect. | **T3** + **T1** |
| 9 | Phone airplane-mode toggle | Like #8 but faster. | 5s + user time | **YES** — `[none]`. | Same as #8. | **T3** + **T1** |
| 10 | Phone WiFi drop → falls back to mobile data | Cameras unreachable (mobile can't reach LAN IPs). | Until WiFi returns | **YES** — `[wifi]` → `[mobile]`. | **Do NOT** reconnect on mobile alone — it won't work. WAIT for `[wifi]` to return. | **T3** (distinguish mobile vs wifi in listener) |
| 11 | RTSP session timeout / idle disconnect | Usually player.stream.completed or player.stream.error after a long idle window (depends on camera firmware). | Instant — immediate retry works | No | Backoff starting from attempt 1; open() will succeed immediately. | **T1** |
| 12 | TCP zombie — connection open, no data arriving (THE zombie scenario per RELY-03) | **No player signal** — stream.playing stays true, completed doesn't fire. `audio-pts` freezes. | Indefinite until watchdog fires | No | Watchdog (D-05/06) detects, forces `player.stop()` + reconnect. | **T2 only** — this is the raison d'être for the zombie detector |
| 13 | Doze mode / Android deep sleep | Android may suspend network callbacks. Player may keep running (foreground service + wake lock), or stall silently. | Indefinite if Doze is aggressive | Likely No | Foreground service + battery-opt exempt (already done in Phase 3) should prevent this, but on-device overnight testing required. | **T1** if stream actually errors; **T2** if it goes zombie |
| 14 | Camera disabled in Protect UI (user action) | `player.stream.error` (RTSP access denied / 404) | Until re-enabled | No | Backoff forever — this is fine; if user re-enables it, next retry succeeds. | **T1** |

**Conclusion — coverage matrix:**
- All 14 modes are covered by at least one trigger.
- Modes 1, 3, 4, 7, 11, 14 rely primarily on **T1 (player event)** — high confidence this works; already used for status transitions today.
- Modes 5, 6, 8, 9, 10 rely primarily on **T3 (connectivity)** — depends on `connectivity_plus` firing reliably for each of these sub-cases (see caveat below).
- Mode 12 requires **T2 (zombie)** — this is why RELY-03 exists.
- Mode 13 (Doze) is the open risk; mitigations already in place from Phase 3 plus on-device overnight validation required.

**Caveat on connectivity_plus reliability:** `[CITED: pub.dev/packages/connectivity_plus]` The docs state "[the stream] doesn't filter events, nor it ensures distinct values" — rapid flaps will generate multiple events. Android debouncing is our responsibility (see Section 3). Also docs note: "Connectivity changes are no longer communicated to Android apps in the background starting with Android O (8.0)." This is why the foreground service is load-bearing — our app is NOT backgrounded for connectivity purposes while the FGS is active.

## Section 2 — media_kit / libmpv Behavior for Reconnection

### `player.open()` on same instance
**[CITED: https://medium.com/@pranav.tech06/building-a-fault-tolerant-live-camera-streaming-player-in-flutter-with-media-kit-28dcc0667b7a]** Author confirms reuse pattern: "Whenever an error or completion event occurs, the player reopens the same HLS stream automatically through error stream listening." Instance reuse works; dispose is not required. Also cited for zombie detector: author uses a 5s periodic watchdog comparing positions across 3 checks (15s) to detect freeze, then `player.stop()` + 200ms delay + `player.open()`.

Our existing code in `audio_player_provider.dart:606-614` already does `player.open()` on the same instance in `switchQuality()`. This pattern is proven against our own stack.

### mpv property persistence across `player.open()`
**[ASSUMED]** Not explicitly documented. We currently call these in `startMonitoring` BEFORE the first `open()`:
- `demuxer-lavf-o` = `rtsp_transport=tcp`
- `cache` = `yes`
- `demuxer-max-bytes` = `512KiB`
- `demuxer-readahead-secs` = `2`
- `cache-pause` = `no`
- `audio-buffer` = `settings.audioBufferSeconds.toString()`
- `vid` = `no` (after open, not before)

**Planner action:** add a helper `_applyPlaybackTuning(nativePlayer)` and call it **every time** before `open()` — on initial connect AND on every reconnect. This avoids depending on property persistence. Cost: ~10ms extra per reconnect (negligible). Benefit: zero risk from property reset.

### `player.open()` timeout behavior
**[CITED: https://github.com/mpv-player/mpv/issues/3361]** Historical issue: setting `--network-timeout` on RTSP streams CAUSES failures (stream refuses to start). The default is "0" / disabled, which means `open()` may hang indefinitely waiting for connect on a dead host. In practice, mpv's underlying FFmpeg demuxer has its own internal TCP connect timeout (~20-30s typical for SYN retries on Linux/Android). Our existing reconnect loop should NOT `await player.open()` without a surrounding timeout.

**Recommendation:** wrap `open()` in `Future.any([openFuture, Future.delayed(Duration(seconds: 15), () => throw TimeoutException(...))])`. 15s is longer than a typical LAN TCP SYN retry cycle but short enough that the backoff doesn't stall. Do NOT set the mpv `network-timeout` property — it has known RTSP incompatibility.

### Signals the stream is actually producing audio
Our existing `_lastAudioPts` tracking in `audio_player_provider.dart:339-342` is the correct primitive. mpv's `audio-pts` property advances with stream decode progress. Stall = no advance for N seconds. `[VERIFIED: mpv-doc snippet]` `audio-pts` "reports the current audio presentation timestamp" and freezes at the last valid value when data stops arriving.

### D-06 zombie signal details

| Signal | mpv property / media_kit API | Known quirks | Can be legitimately 0/stale? |
|--------|-------------------------------|--------------|------------------------------|
| (1) `audio-pts` stall | `NativePlayer.getProperty('audio-pts')` — already in use | Can be empty string at stream-start; handled by `double.tryParse(ptsStr) ?? 0.0` | At stream-start for ~1–3s (before first decode). During legitimate silence, `audio-pts` DOES still advance (decoder processes silence samples) — so a true stall is a hard signal. |
| (2) `Player.stream.buffering` stuck `true` | Already subscribed in `audio_player_provider.dart:106-122` | Buffering can legitimately be true during brief network jitter (sub-second flaps) | Rare for true buffering to persist >10s on healthy LAN RTSP |
| (3) `audio-bitrate` sustained 0 | `NativePlayer.getProperty('audio-bitrate')` — already polled in `audio_player_provider.dart:372` | **Yes — can legitimately be 0 at stream start before metadata arrives.** Also can flap during decoder transitions. | **Yes at start + occasional flaps.** MUST combine with PTS stall — bitrate==0 alone is too noisy. |
| (4) No new `Player.stream.audioParams` events | Already subscribed in `audio_player_provider.dart:124-131`; need to track last-event timestamp | audioParams fires on stream reinitialization. During healthy steady-state playback, **audioParams is sparse** — a single event at connect and then silent for the whole session. **This signal alone is a weak indicator of health.** | YES — in steady state no audioParams events are expected. This signal best used to DETECT a silent reinit, not continuous health. |

**Recommendation for D-06 combination logic:**
- **Use quorum ≥ 2.** OR-combining would false-positive at stream start (bitrate=0 + no-audioParams both trigger in the first 3 seconds, before PTS advances).
- Best pairs: signal (1) PTS stall + signal (2) buffering-stuck is the strongest "real zombie" pattern — both are specific, both imply no data flow.
- Weighted alternative (optional): give signal (1) weight 2, signals (2)(3)(4) weight 1 each, fire at score ≥ 2. Equivalent to "PTS-stall alone OR any two of the others."

## Section 3 — connectivity_plus Integration

### Subscription pattern
`[VERIFIED: Context7 docs]` Use `Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> result) {...})`. Returns a list because Android can have multiple active transports simultaneously (WiFi + VPN, etc.). Always cancel the StreamSubscription.

```dart
// Source: Context7 / connectivity_plus docs
StreamSubscription<List<ConnectivityResult>>? _connSub;

void _startConnectivityListener() {
  _connSub = Connectivity().onConnectivityChanged.listen((results) {
    final hasWifi = results.contains(ConnectivityResult.wifi);
    _onConnectivityChange(hasWifi);
  });
  // Push to _subscriptions list for unified cleanup in existing dispose pattern.
}
```

Add the subscription to the existing `_subscriptions` List in `AudioPlayerNotifier` (`audio_player_provider.dart:23`) so teardown is centralized.

### Debouncing rapid toggles
`[CITED: pub.dev/packages/connectivity_plus]` Docs: "[the stream] doesn't filter events, nor it ensures distinct values." We must debounce.

**Recommended debounce strategy:**

```dart
bool? _lastKnownHasWifi;
Timer? _debounceTimer;

void _onConnectivityChange(bool hasWifi) {
  // Coalesce rapid toggles (≤1s window).
  _debounceTimer?.cancel();
  _debounceTimer = Timer(const Duration(seconds: 1), () {
    if (hasWifi == _lastKnownHasWifi) return;
    final wasOn = _lastKnownHasWifi ?? true;
    _lastKnownHasWifi = hasWifi;

    if (!hasWifi && wasOn) {
      // WiFi went down — mark cameras reconnecting, cancel any open retry timers
      // (they'd just fail). Supervisor will resume on reconnect.
      _onWifiDropped();
    } else if (hasWifi && !wasOn) {
      // WiFi back — trigger immediate reconnect (bypass backoff)
      _onWifiReconnected();
    }
  });
}
```

### Distinguishing WiFi vs cellular
The `results` list contains `ConnectivityResult.wifi`, `ConnectivityResult.mobile`, `ConnectivityResult.none`, etc. Check for `wifi` explicitly — cellular coming online is NOT a reason to attempt reconnect (cameras are on LAN, not reachable via mobile).

```dart
final hasWifi = results.contains(ConnectivityResult.wifi);
final hasEthernet = results.contains(ConnectivityResult.ethernet);  // for macOS dev builds
final lanReachable = hasWifi || hasEthernet;
```

### Connected-but-no-LAN-access
`[CITED: pub.dev/packages/connectivity_plus]` Docs: "connectivity status does not guarantee actual internet access." Same for LAN access — phone may be associated with AP but AP has no uplink.

**For our use case,** link-level connectivity is "necessary but not sufficient." Player.open() failures handle the "associated but can't reach camera" case (TCP connect will fail → stream.error → retry with backoff). We do NOT need an additional ping check. The reconnect loop is the check.

## Section 4 — flutter_local_notifications for the 5-Minute Alert (D-04)

### Channel setup

```dart
// Source: Context7 docs / flutter_local_notifications
const AndroidNotificationChannel alertChannel = AndroidNotificationChannel(
  'baby_monitor_alert',
  'Camera Offline Alerts',
  description: 'Fires when a camera has been offline for 5 minutes',
  importance: Importance.max,          // heads-up notification
  playSound: true,
  enableVibration: true,
  enableLights: true,
  // No custom sound — use system default alarm sound
);
```

### Alert firing

```dart
Future<void> fireAlert({
  required int cameraIdHash,
  required String cameraName,
}) async {
  const details = AndroidNotificationDetails(
    'baby_monitor_alert',
    'Camera Offline Alerts',
    channelDescription: 'Fires when a camera has been offline for 5 minutes',
    importance: Importance.max,
    priority: Priority.high,           // heads-up on lock screen
    category: AndroidNotificationCategory.alarm,  // treated as urgent
    fullScreenIntent: false,           // see FSI restrictions below
    ongoing: false,
    autoCancel: true,
    ticker: 'Camera offline',
  );
  await _plugin.show(
    cameraIdHash,  // unique per camera
    'Camera offline: $cameraName',
    'No audio for 5 minutes. Tap to check.',
    const NotificationDetails(android: details),
  );
}
```

**Notification IDs:** use a stable per-camera int derived from `cameraId.hashCode`. Fine because we never have more than 2-3 cameras and collisions within a single app's notifications are fine (newer overwrites older — that's actually desired behavior here).

### Cancellation on recovery

```dart
Future<void> cancelAlert(int cameraIdHash) async {
  await _plugin.cancel(cameraIdHash);
}
```

### Waking the phone overnight

**[CITED: Android docs / Android 14 FSI restrictions]**
- `Importance.max` + `Priority.high` is sufficient for heads-up + lock-screen display. Phone WILL wake screen for these.
- `fullScreenIntent: true` is MORE aggressive (would display a full-screen activity like an incoming call) but `[CITED: source.android.com/docs/core/permissions/fsi-limits]` Android 14+ **restricts FSI permission to calling/alarm apps only**. A baby monitor does NOT qualify; users would need to manually grant USE_FULL_SCREEN_INTENT permission in settings.
- **Recommendation: skip FSI for v1.** `Importance.max` heads-up is loud enough to wake a sleeping parent; FSI adds permission friction for marginal benefit.

### POST_NOTIFICATIONS permission
Already granted in Phase 3 for the foreground service notification (`monitoring_screen.dart:42-46` calls `FlutterForegroundTask.checkNotificationPermission()` and requests if not granted). **Same permission covers both the FGS notification and the alert notification** — Android's POST_NOTIFICATIONS is app-wide, not channel-specific.

### Doze mode interaction
**[CITED: developer.android.com/training/monitoring-device-state/doze-standby]** Doze DOES affect notifications fired via scheduled alarms (`AlarmManager` / `setExactAndAllowWhileIdle`). But our alert uses an **immediate `.show()`** call, fired when a plain in-process `Timer(5m)` elapses. As long as the Timer fires (which depends on the isolate staying active — see Pitfall 2), the notification will display immediately.

### Interaction with existing foreground_service notification
- FGS channel: `baby_monitor_service` (`foreground_service.dart:24`) — `Importance.LOW`, persistent.
- Alert channel: `baby_monitor_alert` — `Importance.max`, one-shot.
- **Different channels, different IDs** → no collision. FGS notification keeps running; alert appears alongside it. When user dismisses the alert, FGS notification remains.

### AndroidManifest changes
Already has `POST_NOTIFICATIONS`. No new permissions required for a basic Importance.max notification. Do NOT add `USE_FULL_SCREEN_INTENT` (FSI-restricted in Android 14+).

## Section 5 — Reconnect State Machine Design

### Where to hold reconnect state

**Recommended:** new class `ReconnectSupervisor` in `lib/features/monitoring/services/reconnect_supervisor.dart`, held as a field of `AudioPlayerNotifier`. Per-camera fields:

```dart
class _ReconnectState {
  int attempt = 0;                   // current backoff attempt (0 = first attempt)
  Timer? retryTimer;                 // scheduled next retry
  Timer? alertTimer;                 // 5-min alert countdown
  bool alertFired = false;           // one-shot gate (D-04)
  bool inFlight = false;             // dedupe guard (see Pattern 3)
  DateTime? firstDropAt;             // for health summary
}

class ReconnectSupervisor {
  final Map<String, _ReconnectState> _perCamera = {};
  // ...
}
```

Do NOT put this in `CameraAudioState` — that class is UI-visible and should stay immutable & simple. Reconnect state is operational plumbing and UI doesn't need it beyond the `connectionStatus` enum.

### Cancellation on stopMonitoring

Extend existing `stopMonitoring()` in `audio_player_provider.dart:639-657`:

```dart
Future<void> stopMonitoring() async {
  // existing teardown:
  _levelPollTimer?.cancel();
  // NEW:
  _reconnectSupervisor.cancelAll();     // cancel all retryTimers and alertTimers
  _connectivityListener?.cancel();      // cancel connectivity sub
  // existing:
  for (final sub in _subscriptions) { sub.cancel(); }
  // etc.
}
```

The supervisor's `cancelAll` must iterate all `_perCamera` entries and cancel `retryTimer` and `alertTimer`. A leaked timer across stopMonitoring would wake the phone at 3am after the user already stopped monitoring — critical to get right.

### Interleaving the three triggers (D-03)

All three triggers call the same entry point:

```dart
// trigger (a): player stream.error / completed listener (existing line 95-104 extended)
player.stream.error.listen((error) {
  appLog('STREAM', '$cameraName error=$error');
  _reconnectSupervisor.requestReconnect(cameraId, cause: 'player_error');
});
// likewise for .completed

// trigger (b): zombie watchdog (inside _pollAudioLevels)
if (zombieScore >= 2) {
  _reconnectSupervisor.requestReconnect(cameraId, cause: 'zombie');
}

// trigger (c): connectivity listener
_onWifiReconnected() {
  for (final cam in state.value?.cameras ?? []) {
    if (cam.connectionStatus != CameraConnectionStatus.playing) {
      _reconnectSupervisor.requestReconnect(cam.cameraId,
        cause: 'wifi_reconnect',
        immediate: true,  // bypass backoff — network just came back
      );
    }
  }
}
```

The `inFlight` guard (Pattern 3) ensures two triggers arriving in the same 100ms don't each start a reconnect.

### Zombie vs OR vs quorum — the empirical choice

**Recommendation: quorum ≥ 2 of 4 signals.**
- Rationale from Section 2: signals (3) and (4) have legitimate low-signal states. OR would cause false positives at stream-start and during brief buffering events.
- Weighted variant: (1) PTS stall × 2, (2) buffering-stuck × 1, (3) bitrate=0 × 1, (4) no-audioParams × 1; fire at score ≥ 2. Equivalent to "PTS alone OR any two others." This favors signal (1) (the most specific) without requiring it.
- Plan should include a debug-mode log line every time a zombie score transitions ≥1, so field testing can reveal whether false positives happen.

### Defensive recurring async

See Pattern 4 above. The inner timer callback MUST have its own try/catch, AND the catch handler MUST itself try/catch the re-scheduling call. Three layers of defense because this is the most critical overnight path.

## Section 6 — Health Summary Event Stream (MNTR-01)

### Event data structure

```dart
// lib/features/monitoring/models/health_event.dart
enum HealthEventType {
  monitoringStarted,
  monitoringStopped,
  streamStarted,
  streamError,
  reconnectAttempt,
  reconnectSuccess,
  zombieDetected,
  wifiDropped,
  wifiReconnected,
  alertFired,
}

class HealthEvent {
  final DateTime timestamp;
  final String? cameraId;   // null for session-wide events
  final String? cameraName; // cached for display (avoid lookup on render)
  final HealthEventType type;
  final String? detail;     // free-text, e.g. error message or attempt number

  const HealthEvent({
    required this.timestamp,
    required this.type,
    this.cameraId,
    this.cameraName,
    this.detail,
  });
}
```

### Where it lives

**Recommended:** new `HealthEventsNotifier extends Notifier<List<HealthEvent>>` in `lib/features/monitoring/providers/health_events_provider.dart`.

```dart
class HealthEventsNotifier extends Notifier<List<HealthEvent>> {
  static const _maxEvents = 1000;  // D-17

  @override
  List<HealthEvent> build() => const [];

  void record(HealthEvent event) {
    // Write via append; cap at _maxEvents (drop oldest).
    final updated = [...state, event];
    if (updated.length > _maxEvents) {
      updated.removeRange(0, updated.length - _maxEvents);
    }
    state = updated;
  }

  void clear() => state = const [];
}

final healthEventsProvider = NotifierProvider<HealthEventsNotifier, List<HealthEvent>>(
  HealthEventsNotifier.new,
);
```

`AudioPlayerNotifier` reads it via `ref.read(healthEventsProvider.notifier).record(...)`. Do NOT put the list inside `AudioPlayerNotifier` state — AsyncNotifier<MonitoringState> is already doing a lot; adding 1000-item event list churn to its state would thrash UI rebuilds on unrelated consumers.

**Alternative considered:** plain in-memory singleton (like `AppLogger`). Rejected because Riverpod integration gives us automatic UI reactivity on the summary screen for free.

### Rendering
Chronological `ListView.builder`, reverse-scrolled (newest on top). Follow the existing `log_screen.dart` pattern — small monospace text, colored by event type.

Per-camera counters are derived from the list:

```dart
final reconnectCountByCamera = events
  .where((e) => e.type == HealthEventType.reconnectAttempt)
  .fold<Map<String, int>>({}, (acc, e) {
    acc[e.cameraId!] = (acc[e.cameraId!] ?? 0) + 1;
    return acc;
  });
```

Session uptime = `DateTime.now().difference(monitoringStartedEvent.timestamp)`.

### Session boundary

- On `startMonitoring` → `healthEventsProvider.notifier.clear()`, then `record(monitoringStarted)`.
- On `stopMonitoring` → `record(monitoringStopped)`, keep list (so user can open summary after stopping to review).
- Next `startMonitoring` clears.

**Edge case:** if app is killed mid-session, all events are lost. Per D-14 (in-memory only), this is acceptable for v1. The foreground service is what prevents the kill from happening.

### Memory budget

- `HealthEvent` size: ~200 bytes (DateTime 16, 3 strings ~40 each + 1 enum 8 + overhead 50). Call it 250 bytes.
- 1000 events × 250 bytes = **~250 KB**. Negligible.

### Sanity check on the 1000 cap

Worst case: both cameras in continuous reconnect loop. At 30s backoff (steady state), that's 2 cameras × 2 events per attempt (attempt + error) × 120 attempts/hr × 8 hours = **3,840 events/night per camera = 7,680 total**. That EXCEEDS the 1000 cap.

**Implication:** 1000 is too low if a camera is stuck all night. But the cap is "drop oldest" — so we always keep the LAST 1000 events, which is still the most interesting subset (recent history). This is probably fine for v1, with a note to consider raising to 5000 in a future iteration.

**Alternative:** cap per-event-type to force diversity — keep last 200 reconnect_attempts + last 200 of everything else. More complex; not worth v1.

## Section 7 — Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | `flutter_test` (built in) + `mockito ^5.5.0` (already in pubspec) |
| Config file | None — standard Flutter test layout |
| Quick run command | `flutter test test/features/monitoring/reconnect_supervisor_test.dart` |
| Full suite command | `flutter test` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|--------------|
| RELY-01 | Backoff math: attempt 0 → ~1s, 5 → ~30s, 10 → ~30s (capped) | unit | `flutter test test/features/monitoring/backoff_test.dart` | ❌ Wave 0 |
| RELY-01 | Jitter ±20%: 100 samples at attempt 3 all in [6.4, 9.6] seconds | unit | same file | ❌ Wave 0 |
| RELY-01 | Dedup: two requestReconnect in same tick cause only one open() | unit (fake player) | `flutter test test/features/monitoring/reconnect_supervisor_test.dart` | ❌ Wave 0 |
| RELY-01 | Alert fires after 5min of non-playing | unit (fake clock) | same file | ❌ Wave 0 |
| RELY-01 | Alert cancelled + flag reset on recovery | unit (fake clock) | same file | ❌ Wave 0 |
| RELY-01 | Retry forever — 100 consecutive failures still schedule next | unit | same file | ❌ Wave 0 |
| RELY-01 | Backoff resets on success | unit | same file | ❌ Wave 0 |
| RELY-01 | WiFi drop → mark reconnecting; WiFi up → immediate retry | unit (fake connectivity stream) | `flutter test test/features/monitoring/connectivity_listener_test.dart` | ❌ Wave 0 |
| RELY-01 | Connectivity debounce: 3 toggles in 500ms → 1 action | unit (fake clock) | same file | ❌ Wave 0 |
| RELY-01 | Mobile-only (no wifi) does NOT trigger reconnect | unit | same file | ❌ Wave 0 |
| RELY-01 | stopMonitoring cancels all pending retryTimers + alertTimers | unit | `flutter test test/features/monitoring/reconnect_supervisor_test.dart` | ❌ Wave 0 |
| RELY-02 | CameraConnectionStatus enum includes `reconnecting` | unit | `flutter test test/features/monitoring/player_state_test.dart` | ✅ extend existing |
| RELY-02 | CameraAudioCard renders amber + spinner for reconnecting (widget test) | widget | `flutter test test/features/monitoring/camera_audio_card_test.dart` | ❌ Wave 0 |
| RELY-03 | Zombie watchdog: 4 synthetic signals, quorum ≥ 2 → triggers | unit | `flutter test test/features/monitoring/zombie_watchdog_test.dart` | ❌ Wave 0 |
| RELY-03 | Zombie watchdog: single signal (PTS stall only) does NOT trigger | unit | same file | ❌ Wave 0 |
| RELY-03 | Zombie watchdog: on trigger, emits `zombieDetected` event | unit | same file | ❌ Wave 0 |
| RELY-03 | PTS stall counter resets on advance | unit | same file | ❌ Wave 0 |
| MNTR-01 | HealthEventsNotifier: append, cap at 1000, drop oldest | unit | `flutter test test/features/monitoring/health_events_provider_test.dart` | ❌ Wave 0 |
| MNTR-01 | HealthEventsNotifier: clear() empties state | unit | same file | ❌ Wave 0 |
| MNTR-01 | Summary screen renders event list and per-camera counts | widget | `flutter test test/features/monitoring/health_summary_screen_test.dart` | ❌ Wave 0 |
| MNTR-01 | Events appended in chronological order | unit | same file | ❌ Wave 0 |

### What must be manually verified on-device

| Test | Why manual |
|------|------------|
| Overnight 8-hour run, screen off, both cameras playing | Final integration — no substitute for a real Android device |
| Toggle phone WiFi off/on → observe both cameras reconnect within seconds | Requires real Android ConnectivityManager callbacks |
| Reboot WiFi AP physically → observe reconnect happens in 2-5 min | Can't simulate OS network events reliably |
| 5-minute alert fires with screen off and phone idle for 10 min (Doze risk) | Doze mode can only be tested on device, preferably with `adb shell dumpsys deviceidle force-idle` |
| Dismiss alert notification → does NOT fire again until next outage cycle | Requires actual NotificationManager state |
| Pre-existing audio survives a reconnect (no gap beyond backoff delay) | Ear-on-speaker test |

### Sampling Rate
- **Per task commit:** quick run of the specific test file
- **Per wave merge:** `flutter test` full suite
- **Phase gate:** full suite green + manual overnight smoke test documented in verification artifact

### Wave 0 Gaps

- [ ] `test/features/monitoring/backoff_test.dart` — pure math, no mocks needed
- [ ] `test/features/monitoring/reconnect_supervisor_test.dart` — needs FakePlayer (mockito) and FakeClock (`fake_async` package, add as dev dep)
- [ ] `test/features/monitoring/connectivity_listener_test.dart` — needs a controllable `Stream<List<ConnectivityResult>>` fake
- [ ] `test/features/monitoring/zombie_watchdog_test.dart` — synthetic signal inputs
- [ ] `test/features/monitoring/health_events_provider_test.dart` — plain state tests
- [ ] `test/features/monitoring/camera_audio_card_test.dart` — widget test with pumped Riverpod container
- [ ] `test/features/monitoring/health_summary_screen_test.dart` — same
- [ ] Add `fake_async: ^1.3.0` to dev_dependencies for deterministic timer tests

## Section 8 — Known Risks / Pitfalls

### Pitfall 1: Uncaught exception in reconnect timer kills the loop
**What goes wrong:** A single uncaught exception inside a `Timer` callback (e.g., null dereference during reconnect) terminates the timer silently. The retry loop dies. Parent wakes up at 6am to no audio.
**Why it happens:** Dart's `Timer` swallows exceptions into the unhandledError zone by default. Callbacks do NOT auto-restart.
**How to avoid:** Every timer callback wraps its body in try/catch (Pattern 4), AND the catch handler itself schedules a next retry wrapped in its own try/catch. Treat this as belt-and-suspenders.
**Warning signs:** Look for `Unhandled error` in logs. Add an automated test that throws from the fake player's `open()` and asserts that the next retry still gets scheduled.

### Pitfall 2: Android Doze mode silently stalls Timer.periodic and scheduled work
**What goes wrong:** Screen off > 1 hour, phone stationary → Android enters Doze. `Timer.periodic`, `Timer(5m)`, and `AlarmManager.setExact` all get deferred into Doze's maintenance windows (every ~15min to a few hours, increasing stretch). The 5-min alert fires at 5+N minutes, where N could be 30min or more.
**Why it happens:** `[CITED: developer.android.com/training/monitoring-device-state/doze-standby]` "When the device is in Doze, the system defers standard AlarmManager alarms (including setExact() and setWindow())." **Notably, this applies even with an active foreground service — FGS prevents App Standby, NOT Doze.**
**How to avoid:** Phase 3 already requests battery-optimization exemption (`monitoring_screen.dart:48-51`). That exemption is what excludes the app from Doze restrictions. This is load-bearing. **Confirm on-device** that the battery-opt exemption is granted AND Doze doesn't trip for the app during an overnight idle test. If it does:
  - Fallback A: schedule the 5-min alert via `flutter_local_notifications.zonedSchedule()` with `AndroidScheduleMode.exactAllowWhileIdle` — this uses `setExactAndAllowWhileIdle` which is exempt from Doze.
  - Fallback B: the foreground service isolate's `onRepeatEvent` (we currently use `nothing()` per `foreground_service.dart:32`) could ping the main isolate at a longer cadence to nudge timers.
**Warning signs:** Overnight logs show `Monitoring` notification stuck at a stale state for >15 min. Add a debug "heartbeat" log line in `_pollAudioLevels` — if the gap between heartbeats is > 1s, timer got Doze-stalled.

### Pitfall 3: mpv properties reset on `player.open()` reconnect
**What goes wrong:** TCP transport falls back to UDP (lavf-o reset), cache goes back to default (maybe off), rtsp reconnect races.
**Why it happens:** `[ASSUMED]` — not documented either way. Safer to assume reset.
**How to avoid:** Re-apply all six setProperty calls from `startMonitoring` (`audio_player_provider.dart:228-237`) before EVERY `player.open()` in the supervisor. Factor into `_applyPlaybackTuning(np)` helper.
**Warning signs:** After first reconnect, audio latency changes audibly or stream uses UDP (visible in mpv logs via `rtsp_transport=udp` lines).

### Pitfall 4: High-performance WiFi lock from Phase 3 prevents the very WiFi drop we need to detect
**What goes wrong:** We listen for WiFi drops via connectivity_plus. But Phase 3 may have acquired a `WifiLock` that could interact with OS-level WiFi behavior.
**Why it happens:** `allowWifiLock: true` in `foreground_service.dart:35` — this requests a high-perf WiFi lock from flutter_foreground_task.
**How to avoid:** `[VERIFIED: Android docs]` — a `WifiLock.HIGH_PERF` only prevents WiFi radio from dropping to low-power mode. It does NOT prevent network disconnection events from firing (user toggling WiFi off, AP rebooting, signal loss). So connectivity_plus should still fire. But confirm on-device — set `allowWifiLock: false` temporarily if detection doesn't fire and see if behavior changes.
**Warning signs:** WiFi off from Quick Settings → connectivity_plus does NOT emit.

### Pitfall 5: Multiple reconnect triggers arriving within the same millisecond
**What goes wrong:** Player emits `stream.error`, zombie watchdog fires, and WiFi reconnects all within 100ms. Without dedup, three reconnect attempts race and one wins after tearing down the others — or worse, we call `open()` on a player that's concurrently being opened elsewhere.
**Why it happens:** Events are asynchronous; all three listeners can complete dispatch in the same microtask queue frame.
**How to avoid:** `_reconnectInFlight` guard (Pattern 3). First caller sets the flag, subsequent callers log-and-skip. Guard released in `finally`.
**Warning signs:** Logs show `stream_error` and `wifi_reconnected` at identical timestamps, followed by a crash in `player.open()` (e.g., "player disposed"). The guard prevents this.

### Pitfall 6: User denies notification permission
**What goes wrong:** 5-min alert never fires visibly; parent assumes app is working.
**Why it happens:** Android 13+ requires explicit grant; user can deny.
**How to avoid:** On startMonitoring, check `Permission.notification.status`. If denied, show an in-app banner on the monitoring screen: "Notifications disabled — you won't be alerted if a camera goes offline. Tap to enable." Fallback: still log `alert_fired` to the health event stream so the summary screen shows it post-hoc.
**Warning signs:** User reports missed an outage; check device notification settings for the app.

### Pitfall 7: Event list memory growth during pathological reconnect storm
**What goes wrong:** 1000 events are capped, but the list is recreated on every `record()` (`[...state, event]`). During a reconnect storm at 1 event/100ms, we'd create 10 new 1000-item lists per second. GC pressure + UI thrash.
**Why it happens:** Immutable Riverpod state + naive append.
**How to avoid:** Use a circular buffer under the hood, expose an immutable view:
```dart
final _buffer = ListQueue<HealthEvent>();
void record(HealthEvent e) {
  _buffer.addLast(e);
  while (_buffer.length > 1000) _buffer.removeFirst();
  state = List.unmodifiable(_buffer);  // O(n) copy, but n ≤ 1000
}
```
Still O(n) per record, but allocation pattern is gentler on young-gen GC than spread+concat. **Alternative:** debounce state updates to 100ms batches — emit at most 10 state changes/sec even if 100 events arrive. Better for UI thrash, slightly worse for real-time summary.
**Warning signs:** UI stutter during a reconnect storm; profiler shows frequent young-gen GC.

### Pitfall 8: Battery drain from event-sourced reconnects running all night
**What goes wrong:** A pathological case where a camera is down all night → 2 cameras × ~120 attempts/hr × 8hr = ~1920 TCP connect attempts + ~1920 Dart timer allocations. Plus logging I/O to disk.
**Why it happens:** Retry-forever (D-02) is mandatory; we can't skip this.
**How to avoid:** Backoff caps at 30s (D-01), so steady-state is one attempt per 30s per camera — fundamental bound. `appLog` writes to `/tmp/rtsp_mixer.log`; disk I/O is minor but should be throttled or switched to periodic flush. Verify with an overnight battery drain test.
**Warning signs:** >10% battery drain/hr during an outage (vs ~2-3%/hr while playing).

## Section 9 — Standard Stack Summary

| Library | Version | Purpose | Why |
|---------|---------|---------|-----|
| `connectivity_plus` | `^7.1.1` | Subscribe to Android WiFi / mobile connectivity state changes to drive reconnect trigger (c) | Only maintained cross-platform Flutter plugin for this; wraps native `ConnectivityManager.NetworkCallback`. [VERIFIED: pub.dev 2026-04] |
| `flutter_local_notifications` | `^19.0.0` (pinned; see Dart SDK note in Standard Stack table above) | Fire the 5-minute per-camera one-shot alert (D-04) | Industry standard; handles channels, Android 13+ permissions, importance/priority wake-up behavior. [VERIFIED: pub.dev 2026-04] |
| `fake_async` (dev) | `^1.3.0` | Deterministic Timer tests | Standard Dart testing helper for fake clocks. |

**No other new runtime dependencies.** Every other need is met by the existing stack (media_kit for reconnect, Riverpod for state, logging for logs).

## Section 10 — Code References (where Phase 4 integrates)

Integration points with existing code, file:line specific:

| Existing Location | What Changes | Why |
|-------------------|--------------|-----|
| `lib/features/monitoring/models/player_state.dart:1` (enum definition) | Add `reconnecting` to `CameraConnectionStatus` enum | D-09 |
| `lib/features/monitoring/models/player_state.dart:104-138` (`copyWith`) | No change — existing signature supports new enum value | — |
| `lib/features/monitoring/providers/audio_player_provider.dart:23` (`_subscriptions` list) | Add connectivity_plus StreamSubscription to this list | Centralized cleanup |
| `lib/features/monitoring/providers/audio_player_provider.dart:30-56` (`build`) | Add `_reconnectSupervisor = ReconnectSupervisor(...)` init; register `ref.onDispose` hook to cancel supervisor state | Lifecycle |
| `lib/features/monitoring/providers/audio_player_provider.dart:89-162` (`_listenToPlayer`) | Extend `player.stream.error` / `.completed` handlers to call `_reconnectSupervisor.requestReconnect(cameraId, cause: 'player_error')` | Trigger (a) |
| `lib/features/monitoring/providers/audio_player_provider.dart:106-122` (`.buffering` listener) | Already transitions to `connecting` — extend to emit `healthEventsProvider.notifier.record(stream_error)` on entry-to-buffering after playing | Health events |
| `lib/features/monitoring/providers/audio_player_provider.dart:124-131` (`.audioParams` listener) | Already updates streamInfo — extend with `_zombieWatchdog.recordParamsEvent(cameraId)` | Zombie signal (4) |
| `lib/features/monitoring/providers/audio_player_provider.dart:174-310` (`startMonitoring`) | Near end: start connectivity listener; record `monitoringStarted` event; clear health events list | Session start |
| `lib/features/monitoring/providers/audio_player_provider.dart:220-265` (try/catch around initial `open()`) | Extract to `_openStream(...)` helper that both initial connect AND supervisor retry use — avoids code duplication | DRY |
| `lib/features/monitoring/providers/audio_player_provider.dart:228-237` (mpv setProperty calls) | Wrap in `_applyPlaybackTuning(nativePlayer, settings)`; call from both initial open AND supervisor's post-open step | Property persistence hedge (Pitfall 3) |
| `lib/features/monitoring/providers/audio_player_provider.dart:314-432` (`_startLevelPolling` / `_pollAudioLevels`) | Extend `_pollAudioLevels` with per-camera zombie signal-age tracking (incrementing counters) + quorum check | Trigger (b) — piggyback rather than new timer |
| `lib/features/monitoring/providers/audio_player_provider.dart:292-306` (notification text builder) | Extend status string to include `reconnecting` (not just `playing`/`connecting`) | FGS notification |
| `lib/features/monitoring/providers/audio_player_provider.dart:639-657` (`stopMonitoring`) | Add: cancel connectivity sub; cancel supervisor (all timers); record `monitoringStopped` event | Session end |
| `lib/features/monitoring/widgets/camera_audio_card.dart:84-85` (`isConnecting` flag) | Add `isReconnecting` flag; render amber border + spinner for reconnecting state (distinct from connecting's blue LinearProgressIndicator) | D-10 |
| `lib/features/monitoring/widgets/camera_audio_card.dart:114-153` (status row) | Add reconnecting text: "Reconnecting…" with amber color | D-11 |
| `lib/features/monitoring/screens/monitoring_screen.dart:151-163` (AppBar actions) | Add IconButton (`Icons.analytics`) → `Navigator.push` to HealthSummaryScreen | D-16 |
| `lib/core/services/foreground_service.dart:42-56` (`start`) | No change needed — existing `updateNotification` is sufficient | — |
| `lib/features/monitoring/screens/log_screen.dart` (reference) | Copy list-rendering + auto-scroll + filter pattern for HealthSummaryScreen | Consistent UX |

**New files to create:**

| Path | Purpose |
|------|---------|
| `lib/features/monitoring/models/health_event.dart` | HealthEvent record type + HealthEventType enum |
| `lib/features/monitoring/providers/health_events_provider.dart` | Riverpod Notifier |
| `lib/features/monitoring/services/reconnect_supervisor.dart` | Per-camera backoff state + 5-min alert timer + dedup |
| `lib/features/monitoring/services/zombie_watchdog.dart` | Signal-age tracking + quorum logic |
| `lib/features/monitoring/services/connectivity_listener.dart` | connectivity_plus subscription + debounce |
| `lib/core/services/local_notifications.dart` | Plugin init, channel setup, fire/cancel helpers |
| `lib/features/monitoring/screens/health_summary_screen.dart` | MNTR-01 UI — list + per-camera counts |

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `connectivity_plus` `onConnectivityChanged` returned a single `ConnectivityResult` | Now returns `List<ConnectivityResult>` (supports simultaneous transports) | `connectivity_plus` 4.0.0 (2023) | Our code must `.contains(...)` instead of `==`. Docs we fetched reflect this. |
| `flutter_local_notifications` without explicit channel | Channels required (Android 8+) | Android O (2017); plugin since ~v3.x | We must `createNotificationChannel` before first `.show`. Handled in our `local_notifications.dart` init. |
| Full-screen intent freely usable | Restricted to calling/alarm apps on Android 14+ | Android 14 (2023) | **We will NOT use FSI** for Phase 4. `Importance.max` heads-up is sufficient. |

**Deprecated/outdated:**
- **`--network-timeout` on mpv RTSP streams** — known to break RTSP per mpv#3361. Do not set.
- **`media_kit_libs_audio`** — does NOT include RTSP demuxer. Must use `media_kit_libs_video` (already in pubspec). [VERIFIED: `CLAUDE.md` §Core Framework]

## Assumptions Log

Claims tagged `[ASSUMED]` in this research that benefit from user/field confirmation:

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | mpv properties (cache, demuxer-lavf-o, audio-buffer, etc.) may reset on `player.open()` re-invocation on the same Player instance | Section 2 / Pitfall 3 | Low — mitigation is idempotent re-apply of all properties on every open. Overhead ~10ms. |
| A2 | Android foreground service + battery-opt exemption is sufficient to keep `Timer(5m)` firing overnight in Doze mode | Section 9 / Pitfall 2 | **High** — if wrong, the 5-min alert fires late or not at all, defeating D-04. Mitigation: fallback to `flutter_local_notifications.zonedSchedule` with `exactAllowWhileIdle`. Must be validated on-device overnight. |
| A3 | UDM Pro firmware updates (mode #2 in Section 1) may or may not trigger a connectivity_plus event — Android behavior depends on whether the AP stays associated while the router is down | Section 1 | Low — player.error is the secondary trigger; reconnect will still happen, just with backoff instead of immediate. |
| A4 | connectivity_plus emits a `[wifi]→[none]→[wifi]` sequence for a real AP reboot as opposed to a single edge event | Section 1 / Section 3 | Low — our debounce + "state change" logic handles either pattern. |
| A5 | `flutter_foreground_task`'s `allowWifiLock: true` (Phase 3) does NOT suppress user-initiated WiFi toggle events | Pitfall 4 | Medium — if wrong, T3 trigger is broken; T1 trigger still covers most cases. Easy to test: toggle WiFi and watch for connectivity_plus event. |
| A6 | 1000-event cap is acceptable for a worst-case overnight reconnect storm (will cap at "last 1000" — which is fine to review recent history) | Section 6 | Low — user-visible consequence is that the very first events of the session scroll off the list if there's a storm. Acceptable per D-17. |
| A7 | `stream.error` and `stream.completed` fire reliably for EVERY mode 1, 3, 4, 7, 11, 14 in Section 1 (not always a certainty — some media_kit issues document silent failures) | Section 1 | Medium — if a specific mode silently fails, zombie watchdog (T2) is the catch-all. |

## Open Questions (RESOLVED)

1. **Should the health summary survive `stopMonitoring` until the NEXT `startMonitoring`?**
   - What we know: D-13 = session-scoped, but D-16 says user can open the summary from the monitoring screen, and the screen is only visible when monitoring IS running (except briefly on stop).
   - What's unclear: after user taps Stop, can they still open the summary to review the just-ended session?
   - **Recommendation:** RESOLVED: yes — keep last session's events until next startMonitoring (rather than clearing on stop). Clarifies the intent of D-13 ("session-scoped counters reset per session" — but events persist in-memory until explicitly re-cleared on next session). Low implementation cost.

2. **For the zombie detector, should signal (4) "no audioParams" have a 60s grace period after stream start?**
   - What we know: audioParams is sparse in steady state (may fire only once on connect).
   - What's unclear: how to interpret "no new audioParams events for 60s" — does "new" mean "relative to last event" (always true in steady state) or "since the zombie-check started?"
   - **Recommendation:** RESOLVED: interpret as "since reconnect or since stream start" — reset on every audioParams event, but the counter doesn't accumulate beyond that. This makes signal (4) effectively "stream has been quiet in param changes for 60s" which is always true after start. Conclusion: **signal (4) is the weakest; rely on (1) + (2) as primary, weight (4) at 1 in a weighted-quorum approach.**

3. **Should we log the reconnect *cause* string (player_error / zombie / wifi_reconnect) as part of the `reconnect_attempt` event detail?**
   - Recommendation: RESOLVED: yes — diagnostic value for the user reviewing the summary after an outage. Cheap.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Flutter SDK | Everything | ✓ | 3.x (confirmed running) | — |
| Dart SDK | Everything | ✓ | 3.9.2 per pubspec | — |
| Android device | Overnight validation | User-provided | (physical device) | — — on-device test is mandatory for Phase 4 |
| `connectivity_plus` compatible Android API | WiFi detection | ✓ | minSdk 21 (Android 5.0); docs confirm supported | — |
| `flutter_local_notifications` compatible Android API | Alert firing | ✓ | minSdk 21 sufficient for 19.x; AndroidManifest already has POST_NOTIFICATIONS | — |
| Android 14 USE_FULL_SCREEN_INTENT permission | NOT USED in v1 | n/a | — | — (intentionally skipped — see Section 4) |
| `fake_async` (dev) | Deterministic timer tests | ✗ (not in pubspec) | — | Add to dev_dependencies during Plan |

**Missing dependencies with no fallback:** None.

**Missing dependencies with fallback:** None — fake_async is a dev-only add that the plan will include.

## Validation Architecture

See Section 7 for full Phase Requirements → Test Map. Summary:
- **Unit testable:** backoff math, dedupe, zombie quorum, health events cap, debounce, state-machine transitions. ~15 test cases.
- **Widget testable:** CameraAudioCard reconnecting render; HealthSummaryScreen render.
- **On-device only:** overnight Doze behavior; real WiFi drop/reconnect; real foreground service survival.

Validation gate: full `flutter test` green + ONE successful overnight real-device run before marking Phase 4 complete.

## Security Domain

`security_enforcement` — not explicitly configured in `.planning/config.json`. Phase 4 adds:
- Local-only notifications (no network sending) — no new attack surface.
- connectivity_plus (reads network state) — requires `ACCESS_NETWORK_STATE` (already granted in manifest line 6).
- No new authentication, no new storage, no new IPC.

| ASVS Category | Applies | Standard Control |
|---------------|---------|------------------|
| V2 Authentication | no | Phase doesn't touch auth |
| V3 Session Management | no | Phase doesn't manage user sessions |
| V4 Access Control | no | Phase doesn't add new endpoints |
| V5 Input Validation | no | No new user input |
| V6 Cryptography | no | No new crypto operations |
| V10 Malicious Code (notification payload handling) | yes | `flutter_local_notifications` `payload` field — we pass camera name only. Use Dart String interpolation with known camera names from Protect API; no user-typed strings. |

**No new threat patterns specific to this stack.** The phase is internal reliability engineering; attack surface is unchanged.

## Sources

### Primary (HIGH confidence)
- **Context7: `/websites/pub_dev_packages_connectivity_plus`** — API, Stream pattern, caveats about non-distinct events
- **Context7: `/maikub/flutter_local_notifications`** — Channel config, permission request flow, cancel API, full-screen intent
- **Context7: `/media-kit/media-kit`** — Player.open, stream subscription, PlayerConfiguration, dispose pattern
- **pub.dev/packages/connectivity_plus** — version 7.1.1 verified
- **pub.dev/packages/flutter_local_notifications** — version 21.0.0 latest, Dart SDK 3.10 requirement identified
- **pub.dev/packages/flutter_local_notifications/versions/20.0.0** — Flutter 3.22 min confirmed
- **CLAUDE.md §Conventions (Defensive error handling, media_kit FFmpeg build limitations)** — project-local authoritative constraints
- **lib/features/monitoring/providers/audio_player_provider.dart** — existing code read in full (686 lines); integration points cataloged
- **lib/features/monitoring/models/player_state.dart** — CameraConnectionStatus enum, CameraAudioState shape, silenceDuration already present
- **lib/core/services/foreground_service.dart** — MonitoringTaskHandler isolate split, notification update API
- **lib/features/monitoring/screens/monitoring_screen.dart** — POST_NOTIFICATIONS permission flow, battery-opt exemption already wired
- **android/app/src/main/AndroidManifest.xml** — all existing permissions confirmed

### Secondary (MEDIUM confidence)
- **Medium / Pranav Tech: "Building a Fault-Tolerant Live Camera Streaming Player in Flutter (with media_kit)"** — verified via web fetch; confirms Player instance reuse + 3×5s watchdog pattern
- **developer.android.com/training/monitoring-device-state/doze-standby** — fetched; confirmed Doze restrictions apply even with FGS
- **source.android.com/docs/core/permissions/fsi-limits** — cited via WebSearch results; Android 14 FSI restriction
- **GitHub mpv#3361** — fetched; confirmed `--network-timeout` is incompatible with RTSP, should not be set
- **GitHub mpv#8504** — fetched; confirmed RTSP caching must be explicitly enabled via `cache=yes` (we already do this)

### Tertiary (LOW — flagged for validation)
- Specific behavior of mpv properties surviving across `player.open()` re-invocation on same instance (assumption A1)
- Exact connectivity_plus event sequence for UDM Pro firmware update (assumption A3)
- Whether `flutter_foreground_task` WifiLock masks user-initiated WiFi toggles from connectivity_plus (assumption A5)
- Whether 5-min Timer fires reliably overnight with Phase 3's existing battery-opt exemption (assumption A2 — CRITICAL)

## Metadata

**Confidence breakdown:**
- Standard stack (connectivity_plus, flutter_local_notifications versions + usage): **HIGH** — verified on pub.dev and Context7
- Interruption mode taxonomy: **MEDIUM** — 14 modes enumerated, trigger coverage mapped, but some modes have behavior ambiguity ([ASSUMED] items A3, A5)
- Reconnect state machine: **HIGH** — patterns map cleanly to existing Riverpod + try/catch idiom
- Zombie detection: **MEDIUM** — mpv property semantics confirmed, but quorum threshold is an empirical choice that requires field testing
- Doze mode risk (Pitfall 2): **HIGH confidence that the risk exists; MEDIUM confidence that Phase 3's mitigations suffice** — must validate on-device
- Code integration points: **HIGH** — read all existing files, file:line references verified
- Test strategy: **HIGH** — mockito already in pubspec; fake_async is a well-known addition

**Research date:** 2026-04-23
**Valid until:** 2026-05-23 (30 days; stable ecosystem, Flutter / pub packages evolve slowly)

---
*Phase: 04-reliability-overnight-monitoring*
*Research by: gsd-phase-researcher*
