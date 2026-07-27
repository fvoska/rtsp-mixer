import 'package:flutter_test/flutter_test.dart';
import 'package:rtsp_mixer/features/monitoring/helpers/level_dynamics.dart';

/// Feed [detector] a constant [dbfs] for [seconds] simulated seconds at
/// 10 Hz starting at [startMs]. Returns the timestamp after the last sample.
int feedConstant(
  ActivityDetector detector,
  double dbfs, {
  required int startMs,
  required int seconds,
}) {
  var t = startMs;
  for (var i = 0; i < seconds * 10; i++) {
    detector.feed(dbfs, t);
    t += 100;
  }
  return t;
}

void main() {
  group('dbfsToLevel', () {
    test('exact bounds: ceiling maps to 1.0, floor to 0.0', () {
      expect(dbfsToLevel(kMeterCeilingDb), closeTo(1.0, 1e-9));
      expect(dbfsToLevel(kMeterFloorDb), closeTo(0.0, 1e-9));
    });

    test('values outside the bounds are clamped to [0, 1]', () {
      expect(dbfsToLevel(0.0), 1.0);
      expect(dbfsToLevel(-100.0), 0.0);
    });

    test('non-finite input returns 0.0 (never NaN, never throws)', () {
      expect(dbfsToLevel(double.nan), 0.0);
      expect(dbfsToLevel(double.infinity), 0.0);
      expect(dbfsToLevel(double.negativeInfinity), 0.0);
    });

    test('strictly monotonic across in-range levels', () {
      const dbValues = [-55.0, -45.0, -30.0, -15.0, -6.0];
      var prev = -1.0;
      for (final db in dbValues) {
        final level = dbfsToLevel(db);
        expect(level, greaterThan(prev),
            reason: 'level for $db dBFS must exceed level for previous value');
        prev = level;
      }
    });

    test('midpoint of the dB range maps to 0.5 (linear in dB)', () {
      const mid = (kMeterFloorDb + kMeterCeilingDb) / 2;
      expect(dbfsToLevel(mid), closeTo(0.5, 1e-9));
    });
  });

  group('ActivityDetector', () {
    test('reports zero activity before the warmup window has data', () {
      final d = ActivityDetector();
      d.feed(-50.0, 0);
      d.feed(-50.0, 100);
      expect(d.activity, 0.0);
      expect(d.floorDb, anyOf(isNull, lessThanOrEqualTo(-20.0)));
    });

    test('quiet room settles to ~zero activity', () {
      final d = ActivityDetector();
      feedConstant(d, -50.0, startMs: 0, seconds: 30);
      expect(d.activity, lessThan(0.05));
      expect(d.floorDb, closeTo(-50.0, 1.0));
    });

    test('a loud burst over a learned floor produces high activity fast', () {
      final d = ActivityDetector();
      final t = feedConstant(d, -50.0, startMs: 0, seconds: 30);
      // Crying: ~-20 dBFS, 30 dB over the floor → activity ~1.0 within ~1 s.
      feedConstant(d, -20.0, startMs: t, seconds: 2);
      expect(d.activity, greaterThan(0.8));
    });

    test('moderate speech sits between hiss and crying on the 0..1 scale',
        () {
      final d = ActivityDetector();
      final t = feedConstant(d, -50.0, startMs: 0, seconds: 30);
      // Talking: ~12 dB over floor → activity ~0.4, above the "low
      // sensitivity" slider threshold (0.3), below full scale.
      feedConstant(d, -38.0, startMs: t, seconds: 3);
      expect(d.activity, greaterThan(0.3));
      expect(d.activity, lessThan(0.7));
    });

    test('activity decays after sound stops (release smoothing)', () {
      final d = ActivityDetector();
      var t = feedConstant(d, -50.0, startMs: 0, seconds: 30);
      t = feedConstant(d, -20.0, startMs: t, seconds: 2);
      final duringBurst = d.activity;
      feedConstant(d, -50.0, startMs: t, seconds: 15);
      expect(d.activity, lessThan(duringBurst / 2));
      expect(d.activity, lessThan(0.15));
    });

    test('a persistent new noise source is absorbed into the floor', () {
      final d = ActivityDetector();
      // Longer pre-roll so the fan-era minima can dominate the percentile.
      var t = feedConstant(d, -55.0, startMs: 0, seconds: 60);
      // Fan turns on: constant -42 dBFS. Initially activity is nonzero…
      t = feedConstant(d, -42.0, startMs: t, seconds: 5);
      final initial = d.activity;
      expect(initial, greaterThan(0.2));
      // …but after several minutes the floor absorbs it.
      feedConstant(d, -42.0, startMs: t, seconds: 290);
      expect(d.activity, lessThan(initial / 2));
    });

    test('floor is clamped so a constantly-loud camera cannot mask events',
        () {
      final d = ActivityDetector();
      feedConstant(d, -5.0, startMs: 0, seconds: 30);
      expect(d.floorDb, -20.0);
      // Sustained loudness over the clamped floor keeps reading as activity.
      expect(d.activity, greaterThan(0.4));
    });

    test('non-finite samples and time regressions are ignored (never throws)',
        () {
      final d = ActivityDetector();
      final t = feedConstant(d, -50.0, startMs: 0, seconds: 10);
      final before = d.activity;
      d.feed(double.nan, t + 100);
      d.feed(double.infinity, t + 200);
      d.feed(-20.0, t - 5000); // clock went backwards
      expect(d.activity, before);
    });
  });
}
