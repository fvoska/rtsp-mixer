import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:rtsp_mixer/features/monitoring/helpers/audio_level_meter.dart';

void main() {
  group('bitrateToLevel', () {
    test('exact bounds: ceiling (96 kbps) maps to 1.0, floor (2 kbps) to 0.0',
        () {
      expect(bitrateToLevel(96000), closeTo(1.0, 1e-9));
      expect(bitrateToLevel(2000), closeTo(0.0, 1e-9));
    });

    test('values outside the bounds are clamped to [0, 1]', () {
      expect(bitrateToLevel(200000), 1.0);
      expect(bitrateToLevel(500), 0.0);
    });

    test('non-positive input returns 0.0 (never NaN, never throws)', () {
      expect(bitrateToLevel(0), 0.0);
      expect(bitrateToLevel(-5), 0.0);
    });

    test('null / NaN / infinite input returns 0.0 (never NaN, never throws)',
        () {
      expect(bitrateToLevel(null), 0.0);
      expect(bitrateToLevel(double.nan), 0.0);
      expect(bitrateToLevel(double.infinity), 0.0);
      expect(bitrateToLevel(double.negativeInfinity), 0.0);
    });

    test('strictly monotonic across in-range bitrates', () {
      const bpsValues = [3000.0, 8000.0, 20000.0, 48000.0, 90000.0];
      var prev = -1.0;
      for (final bps in bpsValues) {
        final level = bitrateToLevel(bps);
        expect(level, greaterThan(prev),
            reason: 'level for $bps bps must exceed level for previous value');
        prev = level;
      }
    });

    test('geometric midpoint of the bounds maps to 0.5 (log scale)', () {
      final midBps = math.sqrt(2000.0 * 96000.0);
      expect(bitrateToLevel(midBps), closeTo(0.5, 1e-6));
    });
  });

  group('appendLevel', () {
    test('appending to a full list drops the OLDEST and appends LAST', () {
      final history =
          List<double>.generate(kLevelHistoryCapacity, (i) => i / 100.0);
      final result = appendLevel(history, 0.99);
      expect(result.length, kLevelHistoryCapacity);
      expect(result.first, history[1], reason: 'oldest sample dropped');
      expect(result.last, 0.99, reason: 'new sample appended last');
    });

    test('returns a new instance and does not mutate the input', () {
      final history = [0.1, 0.2, 0.3];
      final result = appendLevel(history, 0.4);
      expect(identical(result, history), isFalse);
      expect(history, [0.1, 0.2, 0.3], reason: 'input list unchanged');
      expect(result, [0.1, 0.2, 0.3, 0.4]);
    });

    test('appending to an empty list returns [sample]', () {
      expect(appendLevel(const [], 0.7), [0.7]);
    });

    test('respects a custom capacity', () {
      final result = appendLevel([0.1, 0.2, 0.3], 0.4, capacity: 3);
      expect(result, [0.2, 0.3, 0.4]);
    });
  });

  group('recentVariation', () {
    test('flat signal has zero variation', () {
      final history = List<double>.filled(10, 0.4);
      expect(recentVariation(history), 0.0);
    });

    test('oscillating 0.1/0.9 signal has variation 0.8', () {
      final history = List<double>.generate(
          10, (i) => i.isEven ? 0.1 : 0.9);
      expect(recentVariation(history), closeTo(0.8, 1e-9));
    });

    test('single spike in an otherwise-flat window is spike minus floor', () {
      final history = List<double>.filled(10, 0.2);
      history[7] = 0.9;
      expect(recentVariation(history), closeTo(0.7, 1e-9));
    });

    test('empty and single-element lists return 0.0 without throwing', () {
      expect(recentVariation(const []), 0.0);
      expect(recentVariation(const [0.6]), 0.0);
    });

    test('only the LAST window samples are considered', () {
      // A big swing 15 samples ago in a 20-sample history must NOT register
      // when the window is 10 (the default).
      final history = List<double>.filled(20, 0.3);
      history[4] = 1.0; // 16 samples from the end — outside the window of 10
      expect(recentVariation(history), 0.0);
      // Sanity: the same spike INSIDE the window does register.
      final inWindow = List<double>.filled(20, 0.3);
      inWindow[15] = 1.0; // 5 samples from the end — inside the window
      expect(recentVariation(inWindow), closeTo(0.7, 1e-9));
    });
  });
}
