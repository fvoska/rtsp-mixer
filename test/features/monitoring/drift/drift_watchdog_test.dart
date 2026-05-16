import 'package:flutter_test/flutter_test.dart';
import 'package:rtsp_mixer/features/monitoring/services/drift_watchdog.dart';

void main() {
  group('DriftWatchdog confirm window + cooldown', () {
    late DriftWatchdog watchdog;
    late List<String> fires;

    setUp(() {
      fires = [];
      watchdog = DriftWatchdog(
        onFire: (id, detail) => fires.add('$id|$detail'),
        confirmWindow: const Duration(seconds: 2),
        cooldown: const Duration(seconds: 10),
      );
    });

    void feed({
      String cam = 'cam1',
      required double cache,
      required double threshold,
      int pollMs = 500,
      int times = 1,
    }) {
      for (var i = 0; i < times; i++) {
        watchdog.recordCacheDuration(
          cameraId: cam,
          cacheSeconds: cache,
          thresholdSeconds: threshold,
          pollIntervalMs: pollMs,
        );
      }
    }

    test('cache below threshold never fires', () {
      feed(cache: 1.0, threshold: 1.5, times: 100);
      expect(fires, isEmpty);
    });

    test('cache equal to threshold does not fire (must exceed)', () {
      feed(cache: 1.5, threshold: 1.5, times: 100);
      expect(fires, isEmpty);
    });

    test('cache above threshold for less than confirmWindow does not fire', () {
      // confirmWindow is 2s; 3 polls of 500ms = 1500ms (still under).
      feed(cache: 3.0, threshold: 1.5, times: 3);
      expect(fires, isEmpty);
    });

    test('cache above threshold for >= confirmWindow fires once', () {
      // 4 polls × 500ms = 2000ms == confirmWindow.
      feed(cache: 3.0, threshold: 1.5, times: 4);
      expect(fires.length, 1);
      expect(fires.first, startsWith('cam1|'));
      expect(fires.first, contains('cache=3.00s'));
      expect(fires.first, contains('> 1.50s'));
    });

    test('a dip below threshold resets the over-window accumulator', () {
      // 3 polls over (1500ms) — not enough on its own.
      feed(cache: 3.0, threshold: 1.5, times: 3);
      // One dip resets the accumulator.
      feed(cache: 0.5, threshold: 1.5, times: 1);
      // 3 more polls over — still not enough because the counter restarted.
      feed(cache: 3.0, threshold: 1.5, times: 3);
      expect(fires, isEmpty);
      // One more push over the line and it fires.
      feed(cache: 3.0, threshold: 1.5, times: 1);
      expect(fires.length, 1);
    });

    test('cooldown gates back-to-back fires for the same camera', () {
      // First fire after 4 polls.
      feed(cache: 3.0, threshold: 1.5, times: 4);
      expect(fires.length, 1);
      // Still over-threshold but within cooldown → no second fire even after
      // another confirm window passes.
      feed(cache: 3.0, threshold: 1.5, times: 20);
      expect(fires.length, 1);
    });

    test('reset(cameraId) clears the accumulator but not the cooldown', () {
      // Drive a fire so the cooldown is armed.
      feed(cache: 3.0, threshold: 1.5, times: 4);
      expect(fires.length, 1);
      watchdog.reset('cam1');
      // Cooldown still applies — even after reset, more fires within window
      // are suppressed.
      feed(cache: 3.0, threshold: 1.5, times: 20);
      expect(fires.length, 1);
    });

    test('resetAll() clears both accumulator and cooldown', () {
      feed(cache: 3.0, threshold: 1.5, times: 4);
      expect(fires.length, 1);
      watchdog.resetAll();
      // Fresh state — fires again after confirmWindow.
      feed(cache: 3.0, threshold: 1.5, times: 4);
      expect(fires.length, 2);
    });

    test('different cameras are tracked independently', () {
      feed(cam: 'cam1', cache: 3.0, threshold: 1.5, times: 4);
      feed(cam: 'cam2', cache: 0.5, threshold: 1.5, times: 4);
      expect(fires.length, 1);
      expect(fires.first, startsWith('cam1|'));
      feed(cam: 'cam2', cache: 3.0, threshold: 1.5, times: 4);
      expect(fires.length, 2);
      expect(fires.last, startsWith('cam2|'));
    });

    test('cooldown is per-camera — one camera firing does not block another',
        () {
      // cam1 fires and goes into cooldown.
      feed(cam: 'cam1', cache: 3.0, threshold: 1.5, times: 4);
      expect(fires.length, 1);
      // cam2 should still be free to fire.
      feed(cam: 'cam2', cache: 3.0, threshold: 1.5, times: 4);
      expect(fires.length, 2);
      expect(fires.last, startsWith('cam2|'));
    });

    test('detail string includes both observed cache and threshold', () {
      feed(cache: 2.34, threshold: 0.5, times: 4);
      expect(fires.first, contains('cache=2.34s'));
      expect(fires.first, contains('> 0.50s'));
    });
  });
}
