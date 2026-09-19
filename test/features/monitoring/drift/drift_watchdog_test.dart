import 'package:flutter_test/flutter_test.dart';
import 'package:rtsp_mixer/features/monitoring/services/drift_watchdog.dart';

void main() {
  late DriftWatchdog watchdog;
  late List<String> fires;
  late List<String> speeds;

  setUp(() {
    fires = [];
    speeds = [];
    watchdog = DriftWatchdog(
      onSetSpeed: (id, speed) => speeds.add('$id|$speed'),
      onFire: (id, detail) => fires.add('$id|$detail'),
      hardLimitSeconds: 10,
      confirmWindow: const Duration(seconds: 2),
      cooldown: const Duration(seconds: 10),
    );
  });

  void feed({
    String cam = 'cam1',
    required double cache,
    double target = 0.2,
    double margin = 0.4,
    double speed = 1.1,
    int pollMs = 500,
    int times = 1,
  }) {
    for (var i = 0; i < times; i++) {
      watchdog.recordCacheDuration(
        cameraId: cam,
        cacheSeconds: cache,
        targetSeconds: target,
        engageMarginSeconds: margin,
        catchUpSpeed: speed,
        pollIntervalMs: pollMs,
      );
    }
  }

  group('tier 1: speed catch-up with hysteresis', () {
    test('a cache at or near the target never touches the speed', () {
      feed(cache: 0.0, times: 50);
      feed(cache: 0.2, times: 50);
      // Inside the margin: over by 0.4 exactly is not "> margin".
      feed(cache: 0.6, times: 50);
      expect(speeds, isEmpty);
      expect(fires, isEmpty);
      expect(watchdog.isCatchingUp('cam1'), isFalse);
    });

    test('engages once when the backlog exceeds target + margin', () {
      feed(cache: 0.61, times: 20);
      expect(speeds, ['cam1|1.1']);
      expect(watchdog.isCatchingUp('cam1'), isTrue);
    });

    test('stays engaged inside the hysteresis band', () {
      feed(cache: 1.0);
      // Below the engage line but still above the target: keep trimming.
      feed(cache: 0.5, times: 20);
      feed(cache: 0.21, times: 20);
      expect(speeds, ['cam1|1.1']);
      expect(watchdog.isCatchingUp('cam1'), isTrue);
    });

    test('returns to 1.0 exactly once when the target is reached', () {
      feed(cache: 1.0);
      feed(cache: 0.2, times: 20);
      expect(speeds, ['cam1|1.1', 'cam1|1.0']);
      expect(watchdog.isCatchingUp('cam1'), isFalse);
    });

    test('re-engages after a new stall', () {
      feed(cache: 1.0);
      feed(cache: 0.1);
      feed(cache: 2.0);
      feed(cache: 0.0);
      expect(speeds, ['cam1|1.1', 'cam1|1.0', 'cam1|1.1', 'cam1|1.0']);
    });

    test('uses the caller\'s target, margin and speed (buffered mode)', () {
      feed(cache: 2.4, target: 2.0, margin: 0.5, speed: 1.05, times: 5);
      expect(speeds, isEmpty, reason: '2.4 is inside 2.0 + 0.5');
      feed(cache: 2.6, target: 2.0, margin: 0.5, speed: 1.05);
      expect(speeds, ['cam1|1.05']);
      feed(cache: 2.1, target: 2.0, margin: 0.5, speed: 1.05, times: 5);
      expect(speeds, ['cam1|1.05'], reason: 'still above target');
      feed(cache: 1.9, target: 2.0, margin: 0.5, speed: 1.05);
      expect(speeds, ['cam1|1.05', 'cam1|1.0']);
    });

    test('cameras are tracked independently', () {
      feed(cam: 'a', cache: 1.0);
      feed(cam: 'b', cache: 0.0, times: 10);
      expect(speeds, ['a|1.1']);
      expect(watchdog.isCatchingUp('a'), isTrue);
      expect(watchdog.isCatchingUp('b'), isFalse);
    });

    test('an onSetSpeed exception is swallowed and state still advances', () {
      final wd = DriftWatchdog(
        onSetSpeed: (_, _) => throw StateError('player gone'),
        onFire: (_, _) {},
      );
      expect(
        () => wd.recordCacheDuration(
          cameraId: 'cam1',
          cacheSeconds: 5,
          targetSeconds: 0.2,
          pollIntervalMs: 250,
        ),
        returnsNormally,
      );
      expect(wd.isCatchingUp('cam1'), isTrue);
    });

    test('ignores NaN, infinite and negative readings', () {
      feed(cache: double.nan, times: 10);
      feed(cache: double.infinity, times: 10);
      feed(cache: -1, times: 10);
      expect(speeds, isEmpty);
      expect(fires, isEmpty);
    });
  });

  group('tier 2: hard-limit resync with confirm window + cooldown', () {
    test('a backlog below the hard limit never fires, however long', () {
      // 10.2 = target + hardLimit exactly: must exceed.
      feed(cache: 10.2, times: 100);
      expect(fires, isEmpty);
      expect(speeds, ['cam1|1.1'], reason: 'tier 1 still engages');
    });

    test('over the hard limit for less than the confirm window does not fire',
        () {
      // confirmWindow is 2 s; 3 polls of 500 ms = 1.5 s.
      feed(cache: 30, times: 3);
      expect(fires, isEmpty);
    });

    test('over the hard limit for the confirm window fires once', () {
      feed(cache: 30, times: 4);
      expect(fires.length, 1);
      expect(fires.first, startsWith('cam1|'));
      expect(fires.first, contains('cache=30.00s'));
      expect(fires.first, contains('> 10.20s'));
    });

    test('a dip under the hard limit resets the confirm accumulator', () {
      feed(cache: 30, times: 3);
      feed(cache: 5);
      feed(cache: 30, times: 3);
      expect(fires, isEmpty);
      feed(cache: 30);
      expect(fires.length, 1);
    });

    test('cooldown suppresses a second fire for the same camera', () {
      feed(cache: 30, times: 4);
      feed(cache: 30, times: 40);
      expect(fires.length, 1);
    });

    test('cooldown is per camera', () {
      feed(cam: 'a', cache: 30, times: 4);
      feed(cam: 'b', cache: 30, times: 4);
      expect(fires.length, 2);
    });

    test('an onFire exception is swallowed', () {
      final wd = DriftWatchdog(
        onSetSpeed: (_, _) {},
        onFire: (_, _) => throw StateError('boom'),
        confirmWindow: const Duration(milliseconds: 500),
      );
      expect(
        () => wd.recordCacheDuration(
          cameraId: 'cam1',
          cacheSeconds: 99,
          targetSeconds: 0,
          pollIntervalMs: 500,
        ),
        returnsNormally,
      );
    });
  });

  group('reset', () {
    test('reset clears catch-up state and the confirm accumulator', () {
      feed(cache: 30, times: 3);
      watchdog.reset('cam1');
      expect(watchdog.isCatchingUp('cam1'), isFalse);
      feed(cache: 30, times: 3);
      expect(fires, isEmpty, reason: 'accumulator restarted from zero');
      // A fresh player is at 1.0, so the next over-margin reading engages
      // again rather than assuming the old speed is still applied.
      expect(speeds, ['cam1|1.1', 'cam1|1.1']);
    });

    test('reset keeps the cooldown', () {
      feed(cache: 30, times: 4);
      watchdog.reset('cam1');
      feed(cache: 30, times: 4);
      expect(fires.length, 1);
    });

    test('resetAll clears the cooldown too', () {
      feed(cache: 30, times: 4);
      watchdog.resetAll();
      feed(cache: 30, times: 4);
      expect(fires.length, 2);
    });
  });
}
