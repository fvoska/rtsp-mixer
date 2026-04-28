---
phase: 04-reliability-overnight-monitoring
reviewed: 2026-04-24T00:00:00Z
depth: standard
files_reviewed: 13
files_reviewed_list:
  - lib/core/services/local_notifications.dart
  - lib/features/monitoring/models/health_event.dart
  - lib/features/monitoring/models/player_state.dart
  - lib/features/monitoring/providers/audio_player_provider.dart
  - lib/features/monitoring/providers/health_events_provider.dart
  - lib/features/monitoring/screens/health_summary_screen.dart
  - lib/features/monitoring/screens/monitoring_screen.dart
  - lib/features/monitoring/services/alert_policy.dart
  - lib/features/monitoring/services/connectivity_listener.dart
  - lib/features/monitoring/services/reconnect_supervisor.dart
  - lib/features/monitoring/services/zombie_watchdog.dart
  - lib/features/monitoring/widgets/camera_audio_card.dart
  - lib/main.dart
findings:
  critical: 2
  warning: 5
  info: 4
  total: 11
status: critical
---

# Phase 04: Code Review Report

**Reviewed:** 2026-04-24
**Depth:** standard
**Files Reviewed:** 13
**Status:** critical (2 findings affect correctness of overnight reliability)

## Summary

The Phase 04 implementation generally hews to project conventions: defensive try/catch wrappers are pervasive, ordering of teardown in `stopMonitoring` matches the threat-model contract (T-04-08), and threading is tight (no obvious leaked subscriptions or unscheduled timers). The supervisor / watchdog / alert-policy / connectivity-listener decomposition is clean and testable.

However, two issues will impact the very behaviors this phase exists to deliver:

- **CR-01** — the zombie watchdog is structurally biased toward false-positive fires after ~60 s of healthy playback because two of the four signals (`buffering=false` and `audioParams`) are edge-triggered events that do NOT recur during steady state, while their counters accumulate every tick. A stable stream that simply does not flap will drift to score=2 (buffering-stuck + no-audioParams) and trigger an unnecessary reconnect every minute. PTS-stall weighting saves the design only if PTS is *always* advancing — which is the fragile assumption.
- **CR-02** — `requestReconnect(immediate: true)` (the WiFi-reconnect bypass) is dead code in the steady state it was designed for. The dedup guard (`inFlight || retryTimer.isActive`) returns early before the `immediate` branch is ever reached, so D-03 trigger (c) does not actually bypass backoff when backoff is pending — the retry still waits the full computed delay.

Several `Warning`-level threading and lifecycle issues (initial-buffering-event masking, alert-not-armed for `error` state, spurious initial wifiDropped event) plus minor cleanup items round out the report.

## Critical Issues

### CR-01: ZombieWatchdog will false-positive fire on healthy long-running streams

**File:** `lib/features/monitoring/services/zombie_watchdog.dart:41-63`
**Also:** `lib/features/monitoring/providers/audio_player_provider.dart:200-246`

**Issue:**
`tick()` increments all four signal-age counters by `pollIntervalMs` every poll. Counters are reset only when their corresponding "positive signal" recorder fires:

| Signal | Reset trigger | Recurs during steady state? |
|---|---|---|
| `_ptsStallMs` | `recordPtsAdvance` — called from `_pollAudioLevels` whenever PTS delta > 0.01 | YES — every poll while audio flows |
| `_bufferingStuckMs` | `recordBufferingFalse` — called from `player.stream.buffering` listener on `false` events | NO — only on `true→false` transitions |
| `_bitrateZeroMs` | `recordBitrateNonZero` — called from `_pollAudioLevels` whenever bitrate > 0 | YES — every poll while audio flows |
| `_noAudioParamsMs` | `recordAudioParams` — called from `player.stream.audioParams` listener | NO — `audioParams` only fires when params change |

For a stable RTSP stream that has been playing cleanly for 60s after the initial `buffering=false` and `audioParams` events:

- `_ptsStallMs = 0` (PTS healthy)
- `_bufferingStuckMs ≥ 60000ms` (no buffering=false event since startup)
- `_bitrateZeroMs = 0` (bitrate healthy)
- `_noAudioParamsMs ≥ 60000ms` (no audioParams event since startup)

`zombieScore` = 0 (PTS) + 1 (buffering-stuck) + 0 (bitrate) + 1 (no-audioParams) = **2** → fires.

This is a structural false positive: the watchdog will request a reconnect approximately one minute into every healthy session, then `recordBufferingFalse` and `recordAudioParams` will fire again from the fresh open() events, score drops below 2, latch resets — and the cycle repeats. The "belt-and-suspenders" coverage in D-06 only works if every signal is genuinely periodic OR if the absence of an event truly correlates with degradation. As implemented, "no audioParams for 60s" and "no buffering=false event for 60s" are both *normal* during a healthy stream.

T-04-09 ("False-positive zombie detection during stream startup") claimed mitigation via "Quorum ≥ 2 with PTS-stall weighted 2 ... requires PTS-stall (hard signal) OR two unrelated weak signals." But buffering-stuck + no-audioParams are exactly that pair of weak signals, and they will both naturally fire in steady state.

**Fix:**

Two viable options — pick one:

1. **(Preferred, smallest diff)** Re-weight so the watchdog requires PTS-stall as a necessary condition. Replace the score formula:

   ```dart
   int zombieScore(String cameraId) {
     // PTS-stall is necessary; without it, we never fire.
     if ((_ptsStallMs[cameraId] ?? 0) < thresholdMs) return 0;
     var score = 2; // PTS-stall contributes 2 (D-06 weighting)
     if ((_bufferingStuckMs[cameraId] ?? 0) >= thresholdMs) score += 1;
     if ((_bitrateZeroMs[cameraId] ?? 0) >= thresholdMs) score += 1;
     if ((_noAudioParamsMs[cameraId] ?? 0) >= thresholdMs) score += 1;
     return score;
   }
   ```
   This preserves the spirit of D-06 (PTS-stall ALONE OR PTS-stall + corroboration) while preventing the all-weak-signals false positive. PTS-stall is the only signal that *is* reset every poll during health, so gating on it is sound.

2. **(More invasive)** Make `buffering=false` and `audioParams` truly periodic by polling them every `_levelPollTimer` tick — read `player.state.buffering` (current snapshot) inside `_pollAudioLevels` and call `recordBufferingFalse` if currently false; do the same for `player.state.audioParams.sampleRate != 0`. Then both signals reset every 500ms during health, and the existing quorum logic works.

Either fix should be added with a unit test that simulates "healthy stream for 120s with only PTS feeding" and asserts the watchdog does NOT fire.

---

### CR-02: WiFi-reconnect `immediate: true` bypass is unreachable in normal operation

**File:** `lib/features/monitoring/services/reconnect_supervisor.dart:69-105`
**Also:** `lib/features/monitoring/providers/audio_player_provider.dart:741-755`

**Issue:**
`requestReconnect` performs dedup before honoring the `immediate` flag:

```dart
if (st.inFlight || (st.retryTimer?.isActive ?? false)) {
  appLog('RECONNECT', '$cameraId: suppressed duplicate ($cause)');
  return;
}
```

In the typical D-03 trigger (c) scenario:
1. RTSP stream fails (e.g., WiFi drops mid-night) → `player.stream.error` fires → `requestReconnect(cause: 'player_error')` → schedules a retry timer (e.g., 8s into a backoff curve).
2. WiFi reconnects 0–30s later → `_onWifiReconnected` calls `requestReconnect(cause: 'wifi_reconnect', immediate: true)` for the non-playing camera.
3. The dedup guard sees `retryTimer.isActive == true` and returns early — **the immediate-mode branch never runs**.

Effect: the camera waits the full backoff delay (up to 30s) even though the network is back. D-04's 5-minute alert clock is also still running. Defeats the purpose of trigger (c), which exists specifically so the parent does not wait through a stale backoff after the network recovers.

This contradicts the threat model claim in T-04-18: *"Immediate-mode bypass only applies after a legitimate `none → wifi` transition."* In code, immediate-mode bypass cannot apply at all when a retry is pending.

**Fix:**

Reorder so `immediate: true` cancels the pending timer and proceeds, while the dedup guard still applies to non-immediate triggers:

```dart
Future<void> requestReconnect(
  String cameraId, {
  required String cause,
  bool immediate = false,
}) async {
  final st = _perCamera.putIfAbsent(cameraId, () => _ReconnectState());

  if (immediate) {
    // WiFi-reconnect bypass: cancel pending retry, but still respect inFlight
    // (an attempt currently executing must complete before a new one starts).
    if (st.inFlight) {
      appLog('RECONNECT', '$cameraId: immediate request suppressed (in-flight)');
      return;
    }
    st.retryTimer?.cancel();
    st.inFlight = true;
    st.firstDropAt ??= DateTime.now();
    onStatusChange(cameraId, ReconnectStatus.reconnecting);
    onEvent(ReconnectEventType.reconnectAttempt, cameraId,
        'attempt ${st.attempt} (cause=$cause, immediate)');
    try {
      await _attemptReconnect(cameraId);
    } catch (_) {
      // _attemptReconnect already rescheduled on failure.
    } finally {
      st.inFlight = false;
    }
    return;
  }

  // Non-immediate path: dedup as before.
  if (st.inFlight || (st.retryTimer?.isActive ?? false)) {
    appLog('RECONNECT', '$cameraId: suppressed duplicate ($cause)');
    return;
  }
  st.inFlight = true;
  st.firstDropAt ??= DateTime.now();
  onStatusChange(cameraId, ReconnectStatus.reconnecting);
  onEvent(ReconnectEventType.reconnectAttempt, cameraId,
      'attempt ${st.attempt} (cause=$cause)');
  try {
    _scheduleRetry(cameraId, computeBackoff(st.attempt, random: _random));
  } finally {
    st.inFlight = false;
  }
}
```

Add a unit test that proves: with a pending retry timer, `requestReconnect(..., immediate: true)` cancels the timer and invokes `onAttempt` synchronously.

---

## Warnings

### WR-01: Camera in `error` state at start never arms a 5-min alert

**File:** `lib/features/monitoring/providers/audio_player_provider.dart:391-397`

**Issue:**
When `player.open(...)` throws synchronously inside `startMonitoring` (catch at line 391), the camera's `connectionStatus` is set to `error` and `errorMessage` is recorded — but no reconnect supervisor request is enqueued, no alert timer is armed, and the supervisor never receives a status change for this camera. The camera will sit in `error` indefinitely with no 5-minute alert ever firing — even though the user has been waiting on a non-`playing` state for the full duration. This violates D-04 ("a camera has been in a non-`playing` state for **5 continuous minutes**") for the case where the *initial* connect fails.

The supervisor only kicks in via `player.stream.error` (post-open), `player.stream.completed`, zombie detection, or WiFi reconnect. None of those trigger when `player.open()` itself throws before the player is even in a streaming state.

**Fix:**

In the `catch (e)` block at line 391, also arm the alert and enqueue a reconnect request so the supervisor takes ownership:

```dart
} catch (e) {
  appLog('AUDIO', 'Error connecting to $cameraName: $e');
  camState = camState.copyWith(
    connectionStatus: CameraConnectionStatus.error,
    errorMessage: e.toString(),
  );
  // D-04: a failed initial open must still arm the 5-min alert clock.
  _alertPolicy.armIfAbsent(camera.id);
  // RELY-01: hand the camera off to the supervisor so retries continue.
  // Use cause: 'initial_open_failed' so the cause chain is auditable.
  unawaited(_reconnectSupervisor.requestReconnect(
    camera.id,
    cause: 'initial_open_failed',
  ));
}
```

(Adjust the `unawaited` import or use `// ignore: unawaited_futures` per the project's existing pattern at `main.dart:17`.)

---

### WR-02: ConnectivityListener emits spurious `wifiDropped` on cellular-only startup

**File:** `lib/features/monitoring/services/connectivity_listener.dart:50-68`

**Issue:**
`_lastKnownHasLan` defaults to `null`. On the first debounced event:
- Line 55: `final wasOn = _lastKnownHasLan ?? true;` — `wasOn` defaults to `true`.
- If the device starts on cellular only (no WiFi/Ethernet), the first event has `lanReachable=false`, `wasOn=true`, so `onDropped()` fires.

This records a `wifiDropped` HealthEvent at startup even though no LAN was ever connected during this session. The user reading the health summary will see a spurious "WiFi lost" entry at t≈0.

**Fix:**

Initialize `_lastKnownHasLan` synchronously before subscribing to the stream, using `Connectivity().checkConnectivity()`:

```dart
Future<void> start() async {
  _sub?.cancel();
  // Seed initial state so the first debounced event compares against truth,
  // not the default-true fallback.
  try {
    final initial = await Connectivity().checkConnectivity();
    _lastKnownHasLan = initial.contains(ConnectivityResult.wifi) ||
        initial.contains(ConnectivityResult.ethernet);
  } catch (e) {
    appLog('CONN', 'checkConnectivity failed (non-fatal): $e');
    _lastKnownHasLan = null; // fall back to existing behavior
  }
  _sub = _stream.listen((results) { ... });
  ...
}
```

(Will require changing `start()` to `Future<void>` and updating `audio_player_provider.dart:445` to `await _connectivityListener.start();` — wrap in the existing try/catch.)

---

### WR-03: `audio-pts` in `_pollAudioLevels` resets to 0 on stream restart, miscomputes `flowing` for one tick

**File:** `lib/features/monitoring/providers/audio_player_provider.dart:472-491`

**Issue:**
After `_performReconnectOpen` completes, the new stream's `audio-pts` typically starts back near 0. But `_lastAudioPts[cam.cameraId]` still holds the LAST pts from the previous stream (could be e.g. 3600.0 after an hour of play). On the next poll:

```dart
final ptsDelta = pts - lastPts; // e.g. 0.5 - 3600.0 = -3599.5
_lastAudioPts[cam.cameraId] = pts;
final flowing = ptsDelta > 0.01;  // false → flowing=false
```

For one tick after every reconnect, `flowing` is incorrectly `false`, causing `recordPtsAdvance` to be skipped that tick and `silenceDuration` to incorrectly accumulate 500ms. Self-corrects on the next poll, but during a reconnect storm this could trigger `isSuspiciouslySilent` (>10s of silence) flagging incorrectly.

**Fix:**

Reset PTS tracking at the same place the watchdog is reset — inside `_applyReconnectStatus` when transitioning to `playing`:

```dart
if (status == ReconnectStatus.playing) {
  try { _zombieWatchdog.reset(cameraId); } catch (e) { ... }
  // Reset PTS tracking so the first poll after reconnect doesn't compute a
  // negative ptsDelta against a stale baseline from the prior stream.
  _lastAudioPts.remove(cameraId);
  _baselineLevel.remove(cameraId);
}
```

---

### WR-04: `_perCamera` map in supervisor never reset between sessions across `stopMonitoring → startMonitoring`

**File:** `lib/features/monitoring/services/reconnect_supervisor.dart:64, 168-175`

**Issue:**
`cancelAll()` clears `_perCamera`, which is good. However, this is invoked from `stopMonitoring` AND `onDispose`. Confirmed clean. **No fix needed** — flagging only because the threat model T-04-08 specifically calls out ordering, and the current ordering is correct (line 1002-1004 in `audio_player_provider.dart`: `_reconnectSupervisor.cancelAll()` is called BEFORE the `for (final player in _players.values) { await player.dispose(); }` loop). Verified compliant.

Demoting this to **Info** retroactively — leaving the entry under Warnings only as a marker that this was checked. (See IN-04.)

---

### WR-05: `requestReconnect`'s outer try/catch in supervisor swallows `_attemptReconnect` errors silently in `immediate: true` path

**File:** `lib/features/monitoring/services/reconnect_supervisor.dart:91-104`

**Issue:**
When `immediate: true`, `_attemptReconnect` is awaited directly. On failure it logs, schedules the next retry via `_scheduleRetry`, then `rethrow`s (line 162). The outer try/catch at line 99-101 catches the rethrow with an underscore (anonymous) and silently discards it. The comment on line 100 reads "_attemptReconnect already rescheduled" — true — but if the reschedule itself failed silently (the inner catch on line 154 logs but does NOT rethrow), the supervisor is now in a state where `inFlight=false` (finally), `retryTimer` is null, and nobody will re-kick the loop until `player.stream.error` fires again. For a Player that's already in a deeply broken state, error events may have stopped firing.

This is the "double catch" comment at line 126-133 of `_scheduleRetry` admitting the failure mode. The threat model T-04-07 claims this is mitigated by "the stream.error listener re-kicking us" — but if the Player is stuck silent without firing errors, no re-kick happens.

**Fix:**

Add a fallback recovery path: if `_scheduleRetry` itself fails, fall back to a long timer (e.g., 60s) before giving up. This is preferable to relying on stream.error which may not fire:

```dart
} catch (schedErr) {
  appLog('RECONNECT',
      '$cameraId: scheduling itself failed ($schedErr) — installing fallback 60s timer');
  // Last-resort 60s timer so we don't depend on stream.error firing.
  Timer(const Duration(seconds: 60), () {
    _perCamera[cameraId]?.retryTimer = null;
    requestReconnect(cameraId, cause: 'fallback_after_schedule_failure');
  });
}
```

This is belt-and-suspenders for an unlikely path, but the project's "no exception may kill a running audio stream" convention argues for it.

---

## Info

### IN-01: Dead field `_ReconnectState.alertTimer` unused

**File:** `lib/features/monitoring/services/reconnect_supervisor.dart:11, 171`

**Issue:**
`_ReconnectState.alertTimer` is declared and cancelled in `cancelAll()` but never assigned anywhere in the supervisor — alert timers live in `AlertPolicy`, which is a separate class. The supervisor doc comment says "set by Plan 04" but Plan 04 (`alert_policy.dart`) does not touch supervisor state. The field is permanently null and the cancel is a no-op.

**Fix:** Remove `Timer? alertTimer;` from `_ReconnectState` and the `st.alertTimer?.cancel();` line in `cancelAll`.

---

### IN-02: Supervisor's `_scheduleRetry` inner-catch reschedule comment misleads

**File:** `lib/features/monitoring/services/reconnect_supervisor.dart:117-135`

**Issue:**
Lines 122-132 contain a try block whose body is only a comment:

```dart
try {
  // _attemptReconnect already incremented attempt + called _scheduleRetry
  // before rethrowing on failure. No second schedule needed here.
} catch (_) {
  // Double-catch...
}
```

The empty try/catch is dead defensive code — there's nothing inside the try that can throw, so the catch is unreachable. The comment about the double-catch suggests the author intended a fallback schedule but documented it as already handled. Either restore the fallback (per WR-05) or delete the empty try/catch and the misleading comment.

**Fix:** Remove the empty try/catch and replace with a clarifying log:

```dart
} catch (e, stack) {
  appLog('RECONNECT', '$cameraId: retry crashed: $e\n$stack');
  // _attemptReconnect already rescheduled on failure (see line ~152).
  // If that scheduling itself failed, the per-poll watchdog or stream.error
  // listener is the recovery path of last resort.
}
```

---

### IN-03: `_recordReconnectEvent` silently swallows all errors (including programmer errors)

**File:** `lib/features/monitoring/providers/audio_player_provider.dart:758-778`

**Issue:**
The whole body of `_recordReconnectEvent` is wrapped in `try { ... } catch (e) { appLog('RECONNECT', 'Failed to record event: $e'); }`. This is correct per the "no exception kills the stream" rule, but the `cameraName` lookup, enum mapping, and provider write are all defensive operations — any of them throwing means a real bug (state corruption, disposed provider). Worth a slightly more descriptive log so debugging via `LogScreen` later is easier:

```dart
appLog('RECONNECT',
    'Failed to record reconnect event (type=$type cameraId=$cameraId): $e');
```

---

### IN-04: Multiple defensive try/catch blocks discard the exception (`catch (_)`)

**File:** `lib/features/monitoring/providers/audio_player_provider.dart:91-95, 574-576, 593-594, 1048, 1058`

**Issue:**
The build-time onDispose (line 91-95) and several other locations use `catch (_)` and discard the exception entirely with no log. While this is consistent with "do not let teardown crash the app," it makes overnight bug forensics harder — a silent failure during dispose is invisible in `LogScreen`.

**Fix:**

Replace `catch (_) {}` with `catch (e) { appLog('AUDIO', 'onDispose ${component} threw: $e'); }` everywhere it appears in `_pollAudioLevels`, `onDispose`, and `_saveMixState`/`_loadMixState`. Cost: 5 minutes; benefit: a paper trail for any silent overnight failure.

---

## Verification of Threat Model Coverage

Spot-checked the threat model claims against the code:

| Threat ID | Claim | Verified |
|---|---|---|
| T-04-07 | Three-layer defensive try/catch, retry-forever | PARTIAL — see WR-05 (the inner empty try/catch in `_scheduleRetry` is dead code) |
| T-04-08 | Supervisor cancelled before player.dispose | YES — `audio_player_provider.dart:1002-1004` precedes `_players.dispose()` at line 1016-1019 |
| T-04-09 | Quorum ≥ 2 with PTS-stall weighted 2 prevents false positives | NO — see CR-01 (steady-state false positive) |
| T-04-10 | `_fired` latch prevents repeated fires | YES — `zombie_watchdog.dart:50-62` |
| T-04-13 | onFire wrapped in try/catch in watchdog AND each call site | YES — `zombie_watchdog.dart:55-58` + `audio_player_provider.dart:486-490, 521-526, 569-572` |
| T-04-18 | Immediate-mode bypass only after legitimate none→wifi | NO — see CR-02 (dedup guard precludes any bypass when retry is pending) |
| T-04-22 | Alert callback try/catch + WiFi reconnect callback try/catch | YES — `alert_policy.dart:33-43` + `connectivity_listener.dart:53-67` + `audio_player_provider.dart:744-752` |
| T-04-24 | `alertFired` event still recorded when notification fails | YES — `audio_player_provider.dart:71-79` records BEFORE catching (the LocalNotificationsManager.fireAlert call is non-throwing — internally try/catched) |

Two threat-model claims (T-04-09, T-04-18) do not match the code. CR-01 and CR-02 cover them.

---

## D-04 Alert Policy Audit (per `<expectations>`)

**Claim under audit:** "AlertPolicy.armIfAbsent does NOT reset the clock when re-armed during active timer (continuous-outage requirement)"

**Verification:** `alert_policy.dart:31-33`:
```dart
void armIfAbsent(String cameraId) {
  if (_timers.containsKey(cameraId)) return;
  ...
}
```
Idempotent: re-arming during an active timer is a no-op. Clock is preserved across multiple `armIfAbsent` calls between the buffering listener and `_applyReconnectStatus`. Spec-compliant. **PASS.**

The `clear` path resets the timer + clears `_fired`, which is correct per D-04 ("flag resets when that camera returns to `playing`"). **PASS.**

---

## D-03 Trigger (c) Audit (per `<expectations>`)

**Claim under audit:** "WiFi-back triggers requestReconnect with `immediate: true` and only for non-playing cameras"

**Verification:**
- `audio_player_provider.dart:741-755` — iterates `current.cameras`, filters `cam.connectionStatus != CameraConnectionStatus.playing`, calls `requestReconnect(immediate: true)`. Filter correct. **PASS** for filtering.
- `requestReconnect(immediate: true)` semantics — see CR-02. **FAIL**.

---

_Reviewed: 2026-04-24_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
