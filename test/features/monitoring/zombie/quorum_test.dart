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

    test('audioParams silent alone (signal 4) does NOT fire — score would be 1',
        () {
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
