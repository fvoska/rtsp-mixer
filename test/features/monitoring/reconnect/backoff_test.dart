import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:rtsp_mixer/features/monitoring/services/reconnect_supervisor.dart';

void main() {
  group('computeBackoff (D-01 exponential + ±20% jitter, cap 30s)', () {
    test('attempt 0 with zero-jitter random is ~1000ms', () {
      final r = _FixedRandom(0.5); // nextDouble -> 0.5 => jitter factor 1.0
      final d = computeBackoff(0, random: r);
      expect(d.inMilliseconds, 1000);
    });

    test('progression 0..5 is 1, 2, 4, 8, 16, 30 seconds (pre-jitter center)', () {
      final r = _FixedRandom(0.5);
      expect(computeBackoff(0, random: r).inMilliseconds, 1000);
      expect(computeBackoff(1, random: r).inMilliseconds, 2000);
      expect(computeBackoff(2, random: r).inMilliseconds, 4000);
      expect(computeBackoff(3, random: r).inMilliseconds, 8000);
      expect(computeBackoff(4, random: r).inMilliseconds, 16000);
      expect(computeBackoff(5, random: r).inMilliseconds, 30000);
    });

    test('attempt >= 5 is capped at 30s (not 32s, not 64s)', () {
      final r = _FixedRandom(0.5);
      expect(computeBackoff(6, random: r).inMilliseconds, 30000);
      expect(computeBackoff(10, random: r).inMilliseconds, 30000);
      expect(computeBackoff(99, random: r).inMilliseconds, 30000);
    });

    test('100 samples at attempt 3 (base 8s) stay within ±20% jitter [6400, 9600] ms', () {
      final rng = Random(42);
      for (var i = 0; i < 100; i++) {
        final d = computeBackoff(3, random: rng);
        expect(d.inMilliseconds, greaterThanOrEqualTo(6400));
        expect(d.inMilliseconds, lessThanOrEqualTo(9600));
      }
    });
  });
}

/// Deterministic Random for tests — always returns the constant.
class _FixedRandom implements Random {
  _FixedRandom(this.value);
  final double value;
  @override
  double nextDouble() => value;
  @override
  int nextInt(int max) => 0;
  @override
  bool nextBool() => false;
}
