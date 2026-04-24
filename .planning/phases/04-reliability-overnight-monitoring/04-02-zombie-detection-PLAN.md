---
phase: 04-reliability-overnight-monitoring
plan: 02
type: execute
wave: 2
depends_on: [04-01-reconnect-core-PLAN.md]
files_modified:
  - lib/features/monitoring/services/zombie_watchdog.dart
  - lib/features/monitoring/providers/audio_player_provider.dart
  - test/features/monitoring/zombie/quorum_test.dart
autonomous: true
requirements: [RELY-03]
tags: [zombie-stream, watchdog, baby-monitor, rtsp, media_kit, mpv, flutter]

must_haves:
  truths:
    - "ZombieWatchdog tracks four signals per camera: audio-pts stall, buffering-stuck, bitrate-zero, no-audioParams"
    - "Zombie fires when quorum score >= 2 (PTS-stall weight 2; other signals weight 1 each)"
    - "Single signal alone (except PTS stall) does NOT trigger a reconnect — prevents false positives at stream start"
    - "On zombie fire, ReconnectSupervisor.requestReconnect is called with cause='zombie' (D-07 silent recovery)"
    - "Zombie detection piggybacks on existing 500ms _levelPollTimer — no new timer introduced"
    - "Signal-age counters reset to 0 on any positive signal (PTS advance, buffering=false, bitrate>0, audioParams event)"
    - "A zombieDetected HealthEvent is recorded whenever the watchdog fires, with a detail string describing which signals crossed the threshold"
    - "Zombie threshold is hardcoded at 60s per signal (D-05 + D-08); not exposed in AppSettings"
  artifacts:
    - path: "lib/features/monitoring/services/zombie_watchdog.dart"
      provides: "ZombieWatchdog service with per-camera signal-age tracking + quorum logic"
      contains: "class ZombieWatchdog"
    - path: "lib/features/monitoring/providers/audio_player_provider.dart"
      provides: "Watchdog wired to _pollAudioLevels (tick increments, signal feeders) + audioParams listener + buffering listener"
      contains: "_zombieWatchdog"
    - path: "test/features/monitoring/zombie/quorum_test.dart"
      provides: "Unit tests: four-signal quorum (≥2), PTS-only fires, single non-PTS signal does NOT, recovery on positive signal"
  key_links:
    - from: "lib/features/monitoring/providers/audio_player_provider.dart"
      to: "lib/features/monitoring/services/zombie_watchdog.dart"
      via: "_pollAudioLevels feeds signal ticks; buffering + audioParams listeners feed binary signal updates; watchdog calls requestReconnect on fire"
      pattern: "_zombieWatchdog\\.(tick|recordBuffering|recordAudioParams|recordPtsAdvance|recordBitrate)"
    - from: "lib/features/monitoring/services/zombie_watchdog.dart"
      to: "lib/features/monitoring/services/reconnect_supervisor.dart"
      via: "On score >= 2, watchdog invokes supervisor.requestReconnect(cameraId, cause: 'zombie')"
      pattern: "requestReconnect.*cause: 'zombie'"
---

<objective>
Build the zombie-stream watchdog (RELY-03) that detects TCP-open-but-no-audio scenarios where the player never emits an error but audio data has stopped arriving. Wire it into the existing 500ms `_levelPollTimer` plus the `buffering` and `audioParams` listeners. When ≥2 of the 4 signals cross the 60s threshold, force a reconnect via ReconnectSupervisor — silently, with no user-visible toast (D-07). Record a `zombieDetected` health event every time it fires.

Purpose: RELY-03. Zombie is the catch-all for RTSP interruption mode #12 in RESEARCH.md §1 taxonomy — the case where `player.stream.error` NEVER fires. Without this watchdog, the card will stay green while the parent hears nothing.
Output: Pure additive service + minimal integration in AudioPlayerNotifier. No enum changes, no UI changes.
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
@$HOME/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@CLAUDE.md
@.planning/phases/04-reliability-overnight-monitoring/04-CONTEXT.md
@.planning/phases/04-reliability-overnight-monitoring/04-RESEARCH.md
@.planning/phases/04-reliability-overnight-monitoring/04-PATTERNS.md
@.planning/phases/04-reliability-overnight-monitoring/04-VALIDATION.md
@.planning/phases/04-reliability-overnight-monitoring/04-01-SUMMARY.md

<interfaces>
<!-- Key types and contracts. Plan 04-01 completed first; supervisor API is stable. -->

From lib/features/monitoring/services/reconnect_supervisor.dart (created in Plan 04-01):
```dart
class ReconnectSupervisor {
  Future<void> requestReconnect(String cameraId, {required String cause, bool immediate = false});
  void cancelAll();
}
```

From lib/features/monitoring/providers/audio_player_provider.dart (modified in Plan 04-01):
- `_levelPollTimer` is a 500ms `Timer.periodic` driving `_pollAudioLevels()` (lines ~312–316)
- `_lastAudioPts` Map<String, double> already tracks PTS per camera (line 25)
- `player.stream.buffering` listener already exists (lines 105–122) — needs extension to feed watchdog
- `player.stream.audioParams` listener already exists (lines 123–131) — needs extension to feed watchdog
- `_reconnectSupervisor` field exists on AudioPlayerNotifier
- `_tryGetProperty(NativePlayer, String)` helper exists at lines 434–441

From lib/features/monitoring/models/health_event.dart (from Plan 04-01):
- `HealthEventType.zombieDetected` is one of the 10 variants

From .planning/phases/04-reliability-overnight-monitoring/04-RESEARCH.md §Section 2 — D-06 signal details:
- audio-pts stall — advances even during legitimate silence; stall = hard signal
- buffering stuck — rare to persist >10s on healthy LAN; strong signal
- audio-bitrate = 0 — legitimately 0 at stream start; weak alone
- audioParams sparse — fires on stream reinit; weak alone in steady state
- Recommended combination: quorum ≥ 2, PTS-stall weighted 2 (so PTS alone qualifies)
</interfaces>
</context>

<tasks>

<task type="auto" tdd="true">
  <name>Task 1: ZombieWatchdog service — four-signal tracking + quorum logic + health event emission</name>
  <files>
    lib/features/monitoring/services/zombie_watchdog.dart,
    test/features/monitoring/zombie/quorum_test.dart
  </files>
  <read_first>
    - .planning/phases/04-reliability-overnight-monitoring/04-PATTERNS.md §5 (ZombieWatchdog — per-camera map + _tryGetProperty + signal-age counters + quorum score)
    - .planning/phases/04-reliability-overnight-monitoring/04-RESEARCH.md §Section 2 (mpv property details + D-06 signal quirks), §Section 5 (zombie vs OR vs quorum — recommendation), §Open Question #2 (signal 4 audioParams interpretation — use "reset on any audioParams event, accumulate otherwise")
    - .planning/phases/04-reliability-overnight-monitoring/04-CONTEXT.md §decisions D-05 (60s threshold), D-06 (4 signals), D-07 (silent fire via supervisor), D-08 (hardcoded, no settings entry), D-15 (emit zombieDetected event)
    - CLAUDE.md §Conventions > Defensive error handling
    - lib/features/monitoring/services/reconnect_supervisor.dart (from Plan 04-01 — supervisor API)
    - lib/features/monitoring/models/health_event.dart (from Plan 04-01 — HealthEventType.zombieDetected)
    - lib/features/monitoring/providers/audio_player_provider.dart lines 319–441 (polling structure + _tryGetProperty helper — study the analog)
  </read_first>
  <behavior>
    - Test 1: initial state — all four signal-age counters are 0; `zombieScore(cameraId) == 0`.
    - Test 2: PTS stall alone (120 ticks at 500ms = 60000ms of no PTS advance) → score == 2 → fires zombie.
    - Test 3: bitrate=0 alone for 120 ticks → score == 1 → does NOT fire (prevents stream-start false positive).
    - Test 4: bitrate=0 for 120 ticks + audioParams silent for 120 ticks → score == 2 → fires.
    - Test 5: buffering stuck for 120 ticks + bitrate=0 for 120 ticks → score == 2 → fires.
    - Test 6: recovery — after fire, calling `recordPtsAdvance(cameraId)` resets the PTS counter to 0, bringing score back below threshold.
    - Test 7: on fire, the injected `onFire` callback receives `(cameraId, detail)` where detail lists which signals crossed threshold (e.g., `"PTS stall + buffering"`).
    - Test 8: `reset(cameraId)` zeros all four counters and clears any fire-latch.
    - Test 9: `resetAll()` clears every camera's counters.
  </behavior>
  <action>
    Step A — Create lib/features/monitoring/services/zombie_watchdog.dart:

    ```dart
    import '../../../core/logging/app_logger.dart';

    /// RELY-03: detects TCP-open-but-no-audio zombie streams via 4 signals (D-06).
    ///
    /// Ages each signal in milliseconds. When quorum score >= 2, fires the
    /// `onFire` callback (typically → ReconnectSupervisor.requestReconnect).
    /// Hardcoded 60s threshold per signal (D-05, D-08) — not user-configurable.
    ///
    /// Weighting (RESEARCH §Section 5 recommendation):
    /// - PTS stall: weight 2 (most specific signal — advances even during silence)
    /// - buffering stuck: weight 1
    /// - bitrate=0: weight 1 (legitimately 0 at stream start; weak alone)
    /// - no audioParams: weight 1 (sparse in steady state; weak alone)
    /// Fires at score >= 2, i.e., PTS alone OR any two of the others.
    class ZombieWatchdog {
      ZombieWatchdog({
        required this.onFire,
        this.threshold = const Duration(seconds: 60),
      });

      /// Called when quorum score >= 2 for a camera. Detail summarises which
      /// signals crossed (e.g., "PTS stall + buffering stuck").
      final void Function(String cameraId, String detail) onFire;
      final Duration threshold;

      // Signal age in milliseconds per camera (D-06).
      final Map<String, int> _ptsStallMs = {};
      final Map<String, int> _bufferingStuckMs = {};
      final Map<String, int> _bitrateZeroMs = {};
      final Map<String, int> _noAudioParamsMs = {};

      // Latches prevent repeated fires on every tick while a zombie condition persists.
      // Cleared when the score drops back below 2 (typically after reconnect resets signals).
      final Map<String, bool> _fired = {};

      int get thresholdMs => threshold.inMilliseconds;

      /// Tick every poll interval (500ms by default). Increments all four counters
      /// by `pollIntervalMs`. Caller feeds positive-signal resets separately via
      /// the `record*` methods BEFORE calling tick for that camera on the same pass.
      void tick(String cameraId, int pollIntervalMs) {
        _ptsStallMs[cameraId] = (_ptsStallMs[cameraId] ?? 0) + pollIntervalMs;
        _bufferingStuckMs[cameraId] = (_bufferingStuckMs[cameraId] ?? 0) + pollIntervalMs;
        _bitrateZeroMs[cameraId] = (_bitrateZeroMs[cameraId] ?? 0) + pollIntervalMs;
        _noAudioParamsMs[cameraId] = (_noAudioParamsMs[cameraId] ?? 0) + pollIntervalMs;

        final score = zombieScore(cameraId);
        if (score >= 2 && !(_fired[cameraId] ?? false)) {
          _fired[cameraId] = true;
          final detail = _describeFire(cameraId);
          appLog('ZOMBIE', '$cameraId: detected (score=$score, $detail)');
          try {
            onFire(cameraId, detail);
          } catch (e) {
            appLog('ZOMBIE', '$cameraId: onFire callback threw: $e');
          }
        } else if (score < 2 && (_fired[cameraId] ?? false)) {
          // Score dropped — reset the latch so the next zombie can fire again.
          _fired[cameraId] = false;
        }
      }

      /// Positive signal 1: audio-pts advanced during this poll.
      void recordPtsAdvance(String cameraId) => _ptsStallMs[cameraId] = 0;

      /// Positive signal 2: buffering is currently false.
      void recordBufferingFalse(String cameraId) => _bufferingStuckMs[cameraId] = 0;

      /// Negative signal 2: buffering is currently true — age continues.
      /// (No-op by design; tick() handles the accumulation.)
      void recordBufferingTrue(String cameraId) {}

      /// Positive signal 3: audio-bitrate > 0.
      void recordBitrateNonZero(String cameraId) => _bitrateZeroMs[cameraId] = 0;

      /// Positive signal 4: audioParams event fired.
      void recordAudioParams(String cameraId) => _noAudioParamsMs[cameraId] = 0;

      /// Compute weighted quorum score for a camera.
      /// PTS stall weight 2; others weight 1 each. Fire threshold is >= 2.
      int zombieScore(String cameraId) {
        var score = 0;
        if ((_ptsStallMs[cameraId] ?? 0) >= thresholdMs) score += 2;
        if ((_bufferingStuckMs[cameraId] ?? 0) >= thresholdMs) score += 1;
        if ((_bitrateZeroMs[cameraId] ?? 0) >= thresholdMs) score += 1;
        if ((_noAudioParamsMs[cameraId] ?? 0) >= thresholdMs) score += 1;
        return score;
      }

      /// Reset all counters for a camera (call after a successful reconnect).
      void reset(String cameraId) {
        _ptsStallMs[cameraId] = 0;
        _bufferingStuckMs[cameraId] = 0;
        _bitrateZeroMs[cameraId] = 0;
        _noAudioParamsMs[cameraId] = 0;
        _fired[cameraId] = false;
      }

      /// Clear all per-camera state. Call on stopMonitoring + onDispose.
      void resetAll() {
        _ptsStallMs.clear();
        _bufferingStuckMs.clear();
        _bitrateZeroMs.clear();
        _noAudioParamsMs.clear();
        _fired.clear();
      }

      String _describeFire(String cameraId) {
        final parts = <String>[];
        if ((_ptsStallMs[cameraId] ?? 0) >= thresholdMs) parts.add('PTS stall');
        if ((_bufferingStuckMs[cameraId] ?? 0) >= thresholdMs) parts.add('buffering stuck');
        if ((_bitrateZeroMs[cameraId] ?? 0) >= thresholdMs) parts.add('bitrate=0');
        if ((_noAudioParamsMs[cameraId] ?? 0) >= thresholdMs) parts.add('no audioParams');
        return parts.join(' + ');
      }
    }
    ```

    Step B — Replace test/features/monitoring/zombie/quorum_test.dart (the scaffold stub from Plan 04-01 Wave 0 may already exist — overwrite if so, otherwise create). Note: the directory `test/features/monitoring/zombie/` needs to be created; if the stub was not part of Plan 04-01 Wave 0, create it now.

    ```dart
    import 'package:flutter_test/flutter_test.dart';
    import 'package:rtsp_mixer/features/monitoring/services/zombie_watchdog.dart';

    void main() {
      group('ZombieWatchdog quorum logic (D-06 + RESEARCH §Section 5)', () {
        late ZombieWatchdog watchdog;
        late List<String> fires; // (cameraId, detail) flattened to "cameraId:detail"

        setUp(() {
          fires = [];
          watchdog = ZombieWatchdog(
            onFire: (id, detail) => fires.add('$id:$detail'),
          );
        });

        test('initial score is 0 for any camera', () {
          expect(watchdog.zombieScore('cam1'), 0);
        });

        test('PTS stall alone for 60s fires (weight 2)', () {
          // 120 ticks × 500ms = 60000ms (== threshold).
          for (var i = 0; i < 120; i++) {
            watchdog.tick('cam1', 500);
          }
          // All four counters hit threshold because nothing reset them.
          // Specifically PTS reached threshold, hence weight 2 suffices.
          expect(fires.length, 1);
          expect(fires.first, startsWith('cam1:'));
          expect(fires.first, contains('PTS stall'));
        });

        test('bitrate=0 alone (signal 3) does NOT fire — score would be 1', () {
          // Simulate PTS advancing + buffering false + audioParams firing on every tick,
          // so only the bitrate=0 counter is allowed to grow.
          for (var i = 0; i < 120; i++) {
            watchdog.recordPtsAdvance('cam1');
            watchdog.recordBufferingFalse('cam1');
            watchdog.recordAudioParams('cam1');
            watchdog.tick('cam1', 500);
          }
          // Score = 1 (bitrate=0 only, weight 1). Must NOT fire.
          expect(watchdog.zombieScore('cam1'), 1);
          expect(fires, isEmpty);
        });

        test('audioParams silent alone (signal 4) does NOT fire — score would be 1', () {
          for (var i = 0; i < 120; i++) {
            watchdog.recordPtsAdvance('cam1');
            watchdog.recordBufferingFalse('cam1');
            watchdog.recordBitrateNonZero('cam1');
            watchdog.tick('cam1', 500);
          }
          expect(watchdog.zombieScore('cam1'), 1);
          expect(fires, isEmpty);
        });

        test('buffering + bitrate=0 quorum (1 + 1 = 2) fires', () {
          for (var i = 0; i < 120; i++) {
            watchdog.recordPtsAdvance('cam1');
            watchdog.recordAudioParams('cam1');
            watchdog.tick('cam1', 500);
          }
          expect(watchdog.zombieScore('cam1'), 2);
          expect(fires.length, 1);
          expect(fires.first, contains('buffering stuck'));
          expect(fires.first, contains('bitrate=0'));
        });

        test('PTS advance resets the counter and clears the fire latch', () {
          for (var i = 0; i < 120; i++) {
            watchdog.tick('cam1', 500);
          }
          expect(fires.length, 1);
          // Any positive signal on all four counters resets them.
          watchdog.recordPtsAdvance('cam1');
          watchdog.recordBufferingFalse('cam1');
          watchdog.recordBitrateNonZero('cam1');
          watchdog.recordAudioParams('cam1');
          // Single tick won't cross threshold again.
          watchdog.tick('cam1', 500);
          expect(watchdog.zombieScore('cam1'), 0);
        });

        test('reset(cameraId) zeroes all four counters', () {
          for (var i = 0; i < 120; i++) {
            watchdog.tick('cam1', 500);
          }
          watchdog.reset('cam1');
          expect(watchdog.zombieScore('cam1'), 0);
        });

        test('different cameras are tracked independently', () {
          for (var i = 0; i < 120; i++) {
            watchdog.recordPtsAdvance('cam2');
            watchdog.recordBufferingFalse('cam2');
            watchdog.recordBitrateNonZero('cam2');
            watchdog.recordAudioParams('cam2');
            watchdog.tick('cam1', 500);
            watchdog.tick('cam2', 500);
          }
          expect(fires.length, 1);
          expect(fires.first, startsWith('cam1:'));
        });

        test('does NOT re-fire every tick while condition persists (latched)', () {
          for (var i = 0; i < 125; i++) {
            watchdog.tick('cam1', 500);
          }
          expect(fires.length, 1); // latched after first fire
        });
      });
    }
    ```

    Step C — Verify:
      Run `flutter analyze --no-preamble lib test` — zero issues.
      Run `flutter test test/features/monitoring/zombie/quorum_test.dart` — all 9 tests green.
  </action>
  <verify>
    <automated>flutter analyze --no-preamble lib test &amp;&amp; flutter test --reporter expanded test/features/monitoring/zombie/quorum_test.dart</automated>
  </verify>
  <acceptance_criteria>
    - `test -f lib/features/monitoring/services/zombie_watchdog.dart` exits 0
    - `grep "class ZombieWatchdog" lib/features/monitoring/services/zombie_watchdog.dart` exits 0
    - `grep "threshold = const Duration(seconds: 60)" lib/features/monitoring/services/zombie_watchdog.dart` exits 0
    - `grep "int zombieScore(String cameraId)" lib/features/monitoring/services/zombie_watchdog.dart` exits 0
    - `grep "void tick(String cameraId, int pollIntervalMs)" lib/features/monitoring/services/zombie_watchdog.dart` exits 0
    - `grep "void recordPtsAdvance\|recordBufferingFalse\|recordBitrateNonZero\|recordAudioParams" lib/features/monitoring/services/zombie_watchdog.dart` shows ≥ 4 lines
    - `grep "void reset(String cameraId)" lib/features/monitoring/services/zombie_watchdog.dart` exits 0
    - `grep "void resetAll()" lib/features/monitoring/services/zombie_watchdog.dart` exits 0
    - `test -f test/features/monitoring/zombie/quorum_test.dart` exits 0
    - `flutter analyze --no-preamble lib test` exits 0
    - `flutter test test/features/monitoring/zombie/quorum_test.dart` reports all tests passed (9 expected)
  </acceptance_criteria>
  <done>
    ZombieWatchdog is unit-complete. No wiring into AudioPlayerNotifier yet; that's Task 2.
  </done>
</task>

<task type="auto" tdd="true">
  <name>Task 2: Wire ZombieWatchdog into AudioPlayerNotifier — polling tick, signal feeders, supervisor kickoff, zombieDetected event</name>
  <files>
    lib/features/monitoring/providers/audio_player_provider.dart
  </files>
  <read_first>
    - .planning/phases/04-reliability-overnight-monitoring/04-PATTERNS.md §5 (Rule — piggyback on _levelPollTimer, call requestReconnect), §8 (existing listeners to extend)
    - .planning/phases/04-reliability-overnight-monitoring/04-RESEARCH.md §Section 10 (integration points — lines 105–122 buffering, 123–131 audioParams, 319–432 _pollAudioLevels, 639–657 stopMonitoring)
    - .planning/phases/04-reliability-overnight-monitoring/04-CONTEXT.md §decisions D-06 (signal semantics), D-07 (silent fire), D-15 (zombieDetected event)
    - CLAUDE.md §Conventions > Defensive error handling
    - lib/features/monitoring/providers/audio_player_provider.dart (ENTIRE FILE — post-04-01 state; the file now contains ReconnectSupervisor wiring, _applyPlaybackTuning, and extended stream.error/completed listeners)
    - lib/features/monitoring/services/zombie_watchdog.dart (from Task 1)
    - lib/features/monitoring/services/reconnect_supervisor.dart (from Plan 04-01)
  </read_first>
  <behavior>
    - A ZombieWatchdog instance exists on AudioPlayerNotifier; its `onFire` callback calls `_reconnectSupervisor.requestReconnect(cameraId, cause: 'zombie')` AND records a `zombieDetected` health event with `detail` = the signal summary.
    - In `_pollAudioLevels` inner per-camera loop: the watchdog receives positive signals when appropriate (PTS advanced → `recordPtsAdvance`; audio-bitrate > 0 → `recordBitrateNonZero`) and is ticked by `_pollInterval.inMilliseconds` (500) once per camera per pass.
    - The existing `player.stream.buffering` listener is extended: on `buffering=false` → `_zombieWatchdog.recordBufferingFalse(cameraId)`. (buffering=true does nothing — tick() accumulates.)
    - The existing `player.stream.audioParams` listener is extended: every fire → `_zombieWatchdog.recordAudioParams(cameraId)`.
    - On successful reconnect (supervisor's `_performReconnectOpen` resolves without throwing): `_zombieWatchdog.reset(cameraId)` is called to zero counters. (The supervisor already calls `onStatusChange(..., playing)` after success; hook into that or add an explicit reset in `_applyReconnectStatus` when the new status is `playing`.)
    - On `stopMonitoring` and `onDispose`: `_zombieWatchdog.resetAll()` is called alongside `_reconnectSupervisor.cancelAll()`.
  </behavior>
  <action>
    Step A — Import ZombieWatchdog at top of audio_player_provider.dart (with other service imports already added in Plan 04-01):
    ```dart
    import '../services/zombie_watchdog.dart';
    ```

    Step B — Add watchdog field near `_reconnectSupervisor`:
    ```dart
    late final ZombieWatchdog _zombieWatchdog = ZombieWatchdog(
      onFire: (cameraId, detail) {
        // D-07: silent force-reconnect via supervisor.
        appLog('ZOMBIE', '$cameraId: fire -> requestReconnect (detail=$detail)');
        try {
          ref.read(healthEventsProvider.notifier).record(HealthEvent(
                timestamp: DateTime.now(),
                type: HealthEventType.zombieDetected,
                cameraId: cameraId,
                cameraName: _findCameraName(cameraId),
                detail: detail,
              ));
        } catch (e) {
          appLog('ZOMBIE', '$cameraId: failed to record zombie event: $e');
        }
        _reconnectSupervisor.requestReconnect(cameraId, cause: 'zombie');
      },
    );
    ```

    Step C — Extend the `player.stream.buffering` listener in `_listenToPlayer` (currently around lines 105–122 post-04-01). Inside the existing `.listen((buffering) { ... })` body, add at the top (before the status-transition logic):
    ```dart
    try {
      if (!buffering) {
        _zombieWatchdog.recordBufferingFalse(cameraId);
      }
      // buffering=true: no-op; watchdog's tick() accumulates the age.
    } catch (e) {
      appLog('ZOMBIE', 'buffering listener error (non-fatal): $e');
    }
    ```

    Step D — Extend the `player.stream.audioParams` listener (currently around lines 123–131). Inside the existing `.listen((params) { ... })` body, add at the end:
    ```dart
    try {
      _zombieWatchdog.recordAudioParams(cameraId);
    } catch (e) {
      appLog('ZOMBIE', 'audioParams listener error (non-fatal): $e');
    }
    ```

    Step E — Extend `_pollAudioLevels` inner per-camera loop (current lines 326–412). Find the block where `ptsDelta` and `flowing` are computed (lines ~341–346). After setting `_lastAudioPts[cam.cameraId] = pts;` and computing `flowing`, add:
    ```dart
    try {
      if (flowing) {
        _zombieWatchdog.recordPtsAdvance(cam.cameraId);
      }
    } catch (e) {
      appLog('ZOMBIE', 'pts feed error (non-fatal): $e');
    }
    ```

    After the `audioBitrate` has been read (around line 372, `final audioBitrate = double.tryParse(...)`), add:
    ```dart
    try {
      if (audioBitrate != null && audioBitrate > 0) {
        _zombieWatchdog.recordBitrateNonZero(cam.cameraId);
      }
    } catch (e) {
      appLog('ZOMBIE', 'bitrate feed error (non-fatal): $e');
    }
    ```

    At the END of the per-camera try block (BEFORE `} catch (_) { /* Player may be disposed */ }` on line 410), add the tick:
    ```dart
    try {
      _zombieWatchdog.tick(cam.cameraId, _pollInterval.inMilliseconds);
    } catch (e) {
      appLog('ZOMBIE', 'tick error (non-fatal): $e');
    }
    ```

    Step F — Extend `_applyReconnectStatus` (added in Plan 04-01) to reset the watchdog on successful reconnect. Inside that method, after the `state = AsyncData(...)` assignment, add:
    ```dart
    if (status == ReconnectStatus.playing) {
      try {
        _zombieWatchdog.reset(cameraId);
      } catch (e) {
        appLog('ZOMBIE', 'reset error (non-fatal): $e');
      }
    }
    ```

    Step G — Extend `stopMonitoring` — add `_zombieWatchdog.resetAll();` immediately after `_reconnectSupervisor.cancelAll();` (which was added in Plan 04-01 at the start of stopMonitoring).

    Step H — Extend `ref.onDispose` block (lines ~31–44). In addition to the `_reconnectSupervisor.cancelAll()` call added in Plan 04-01, add:
    ```dart
    try { _zombieWatchdog.resetAll(); } catch (_) {}
    ```

    Step I — Verify:
      Run `flutter analyze --no-preamble lib test` — zero issues.
      Run `flutter test` — full suite green.
  </action>
  <verify>
    <automated>flutter analyze --no-preamble lib test &amp;&amp; flutter test --reporter expanded</automated>
  </verify>
  <acceptance_criteria>
    - `grep "ZombieWatchdog(" lib/features/monitoring/providers/audio_player_provider.dart` exits 0
    - `grep "_zombieWatchdog" lib/features/monitoring/providers/audio_player_provider.dart` shows ≥ 6 references (field declaration, listeners, tick, reset, resetAll)
    - `grep "_zombieWatchdog.recordPtsAdvance" lib/features/monitoring/providers/audio_player_provider.dart` exits 0
    - `grep "_zombieWatchdog.recordBufferingFalse" lib/features/monitoring/providers/audio_player_provider.dart` exits 0
    - `grep "_zombieWatchdog.recordAudioParams" lib/features/monitoring/providers/audio_player_provider.dart` exits 0
    - `grep "_zombieWatchdog.recordBitrateNonZero" lib/features/monitoring/providers/audio_player_provider.dart` exits 0
    - `grep "_zombieWatchdog.tick" lib/features/monitoring/providers/audio_player_provider.dart` exits 0
    - `grep "_zombieWatchdog.reset(cameraId)" lib/features/monitoring/providers/audio_player_provider.dart` exits 0
    - `grep "_zombieWatchdog.resetAll()" lib/features/monitoring/providers/audio_player_provider.dart` exits 0 (≥ 2 hits — stopMonitoring + onDispose)
    - `grep "HealthEventType.zombieDetected" lib/features/monitoring/providers/audio_player_provider.dart` exits 0
    - `grep "cause: 'zombie'" lib/features/monitoring/providers/audio_player_provider.dart` exits 0
    - `flutter analyze --no-preamble lib test` exits 0
    - `flutter test` full suite passes (no regressions from Plan 04-01 tests)
  </acceptance_criteria>
  <done>
    Zombie detection runs on the existing 500ms poll timer, wired to all four D-06 signals, fires supervisor.requestReconnect on quorum, emits `zombieDetected` health events, and resets counters after a successful reconnect / on monitoring stop. No new timer added. No UI change. No settings entry (D-08).
  </done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| mpv property layer ↔ Dart isolate | `_tryGetProperty` reads `audio-pts`, `audio-bitrate` via NativePlayer; may return stale or empty strings during stream reinit. |
| ZombieWatchdog ↔ ReconnectSupervisor | Watchdog's `onFire` invokes supervisor; supervisor's dedup guard is the backstop against watchdog thrashing. |

## STRIDE Threat Register

| Threat ID | Category | Component | Disposition | Mitigation Plan |
|-----------|----------|-----------|-------------|-----------------|
| T-04-09 | Denial of Service | False-positive zombie detection during stream startup (bitrate=0 + audioParams silent both naturally true in first 3s) | mitigate | Quorum ≥ 2 with PTS-stall weighted 2 (RESEARCH §Section 5) — requires PTS-stall (hard signal) OR two unrelated weak signals. Signal-age counters start from 0 on session start and are reset on first positive signal. Unit test `quorum_test.dart` asserts bitrate=0-alone and no-audioParams-alone do NOT fire. |
| T-04-10 | Denial of Service | Zombie detection firing continuously while the player cannot recover (e.g., camera permanently powered off) | mitigate | The `_fired` latch prevents re-fire every tick while score >= 2. Fire clears only when score drops below 2 (typically after a positive signal resumes). Supervisor's dedup (`inFlight`) also absorbs rapid triggers. Backoff caps at 30s (D-01). |
| T-04-11 | Tampering | Zombie reset called after `player.stop()` but before `player.open()` completes — window where counters are 0 but no audio flows, masking a legitimate new zombie | accept | 60s threshold is orders of magnitude longer than the ~300ms stop+reopen window. Not a realistic attack or failure surface. |
| T-04-12 | Information Disclosure | Zombie detail strings logged via appLog contain camera internal IDs | accept | Camera IDs are Protect-internal identifiers, not secrets. appLog writes to app-local /tmp file only. |
| T-04-13 | Elevation of Privilege | Exception inside `_zombieWatchdog.onFire` callback tears down the `_pollAudioLevels` timer | mitigate | onFire body wrapped in try/catch inside the watchdog. Each `_zombieWatchdog.*` call site in `_pollAudioLevels` is individually try/caught with `appLog` + continue (CLAUDE.md §Conventions). The outer `try { ... } catch (_) { /* Player may be disposed */ }` on the per-camera loop is the final safety net. |
</threat_model>

<verification>
- `flutter test test/features/monitoring/zombie/quorum_test.dart` passes with 9 tests
- `flutter analyze --no-preamble lib test` exits 0
- Grep confirms all four signal feeders are called from audio_player_provider.dart at the correct sites (stream.buffering listener, stream.audioParams listener, _pollAudioLevels for PTS and bitrate)
- `_zombieWatchdog.tick(...)` is called exactly once per camera per poll pass (inside the per-camera try block before the catch)
- `_zombieWatchdog.reset(cameraId)` is called from `_applyReconnectStatus` when new status is `playing` (so a successful reconnect clears the zombie latch)
- `_zombieWatchdog.resetAll()` appears in both `stopMonitoring` and `onDispose` (matches supervisor teardown ordering)
</verification>

<success_criteria>
- RELY-03 fully covered: zombie watchdog detects 4 signals with quorum ≥ 2, fires silent reconnect via supervisor, records `zombieDetected` health event, and self-resets after recovery.
- No new timer introduced (piggybacks on 500ms `_levelPollTimer`).
- No UI changes, no settings entry — hardcoded 60s threshold per D-05/D-08.
</success_criteria>

<output>
After completion, create `.planning/phases/04-reliability-overnight-monitoring/04-02-SUMMARY.md` documenting: watchdog signal feed sites (4 locations), the quorum weighting applied, the latch-behavior choice, and the zombie reset ordering (on playing status change + on stopMonitoring + on onDispose).
</output>
