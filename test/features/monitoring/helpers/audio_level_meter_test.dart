import 'package:flutter_test/flutter_test.dart';
import 'package:rtsp_mixer/features/monitoring/helpers/audio_level_meter.dart';

/// Poll cadence used throughout: 250 ms, matching [kLevelPollInterval].
const _dt = 0.25;

/// Feed [seconds] of a constant [bps] into [tracker] (through the bitrate
/// preset's dB mapping) and return the last level. `flowing` defaults to
/// true.
double _feed(
  AudioLevelTracker tracker,
  double? bps,
  double seconds, {
  bool flowing = true,
}) {
  var level = tracker.level;
  final ticks = (seconds / _dt).round();
  for (var i = 0; i < ticks; i++) {
    level = _tick(tracker, bps, flowing: flowing);
  }
  return level;
}

double _tick(AudioLevelTracker tracker, double? bps, {bool flowing = true}) =>
    tracker.update(db: bitrateToDb(bps), flowing: flowing, dtSeconds: _dt);

/// A quiet-room baseline: 16 kbps AAC.
const _quietBps = 16000.0;

/// +12 dB above the baseline (16 kbps × 10^1.2 ≈ 253 kbps).
const _loudBps = 253500.0;

void main() {
  group('bitrateToDb', () {
    test('maps bits/sec to 10·log10', () {
      expect(bitrateToDb(1000), closeTo(30.0, 1e-9));
      expect(bitrateToDb(100000), closeTo(50.0, 1e-9));
    });

    test('ten times the bitrate is +10 dB', () {
      final a = bitrateToDb(16000)!;
      final b = bitrateToDb(160000)!;
      expect(b - a, closeTo(10.0, 1e-9));
    });

    test('null / NaN / infinite / non-positive input returns null, never NaN',
        () {
      expect(bitrateToDb(null), isNull);
      expect(bitrateToDb(double.nan), isNull);
      expect(bitrateToDb(double.infinity), isNull);
      expect(bitrateToDb(double.negativeInfinity), isNull);
      expect(bitrateToDb(0), isNull);
      expect(bitrateToDb(-5), isNull);
    });
  });

  group('appendLevel', () {
    test('capacity is 60 s at the poll cadence', () {
      expect(
        kLevelHistoryCapacity,
        kLevelHistorySeconds * 1000 ~/ kLevelPollInterval.inMilliseconds,
      );
    });

    test('appending to a full list drops the OLDEST and appends LAST', () {
      final history =
          List<double>.generate(kLevelHistoryCapacity, (i) => i / 1000.0);
      final result = appendLevel(history, 0.99);
      expect(result.length, kLevelHistoryCapacity);
      expect(result.first, history[1], reason: 'oldest sample dropped');
      expect(result.last, 0.99, reason: 'new sample appended last');
    });

    test('returns a new unmodifiable instance and does not mutate the input',
        () {
      final history = [0.1, 0.2, 0.3];
      final result = appendLevel(history, 0.4);
      expect(identical(result, history), isFalse);
      expect(history, [0.1, 0.2, 0.3], reason: 'input list unchanged');
      expect(result, [0.1, 0.2, 0.3, 0.4]);
      expect(() => result.add(1.0), throwsUnsupportedError);
    });

    test('appending to an empty list returns [sample]', () {
      expect(appendLevel(const [], 0.7), [0.7]);
    });

    test('respects a custom capacity', () {
      final result = appendLevel([0.1, 0.2, 0.3], 0.4, capacity: 3);
      expect(result, [0.2, 0.3, 0.4]);
    });
  });

  group('AudioLevelTracker', () {
    test('starts at level 0 with no calibration', () {
      final t = AudioLevelTracker();
      expect(t.level, 0.0);
      expect(t.floorDb, isNull);
      expect(t.ceilingDb, isNull);
      expect(t.spanDb, kMinSpanDb);
    });

    test('presets carry the right span clamps for their signal', () {
      expect(AudioLevelTracker.pcm().minSpanDb, kPcmMinSpanDb);
      expect(AudioLevelTracker.pcm().maxSpanDb, kPcmMaxSpanDb);
      expect(AudioLevelTracker.bitrate().minSpanDb, kBitrateMinSpanDb);
      expect(AudioLevelTracker.bitrate().maxSpanDb, kBitrateMaxSpanDb);
    });

    test('PCM preset: a quiet room at -55 dBFS, speech at -30, a cry at -12',
        () {
      final t = AudioLevelTracker.pcm();
      double feedDb(double db, double seconds) {
        var level = t.level;
        for (var i = 0; i < (seconds / _dt).round(); i++) {
          level = t.update(db: db, flowing: true, dtSeconds: _dt);
        }
        return level;
      }

      expect(feedDb(-55, 30), closeTo(0.0, 1e-6), reason: 'floor');
      // Mic self-noise wandering ±3 dB stays under a 0.25 trigger.
      expect(feedDb(-52, 3), lessThan(0.25));
      feedDb(-55, 5);
      // Speech: +25 dB over the room, above the trigger but not pinned.
      final speech = feedDb(-30, 3);
      expect(speech, greaterThan(0.5));
      expect(speech, lessThan(1.0));
      feedDb(-55, 5);
      // A cry: +43 dB, full scale.
      expect(feedDb(-12, 3), closeTo(1.0, 1e-6));
    });

    test('nothing is calibrated during warm-up', () {
      final t = AudioLevelTracker();
      _feed(t, _quietBps, kWarmupSeconds - _dt);
      expect(t.floorDb, isNull, reason: 'warm-up must not seed the floor');
      expect(t.level, 0.0);
    });

    test('a steady quiet room reads as silence once calibrated', () {
      final t = AudioLevelTracker();
      final level = _feed(t, _quietBps, 30);
      expect(t.floorDb, isNotNull);
      expect(t.floorDb!, closeTo(bitrateToDb(_quietBps)!, 0.01));
      expect(level, closeTo(0.0, 1e-6));
    });

    test('a +12 dB burst above the quiet floor reads near full scale', () {
      final t = AudioLevelTracker();
      _feed(t, _quietBps, 30);
      final level = _feed(t, _loudBps, 3);
      // Span clamps at kMinSpanDb (6 dB) until the ceiling learns the burst,
      // and 12 dB / 6 dB pins the meter either way.
      expect(level, closeTo(1.0, 1e-6));
      expect(t.ceilingDb, isNotNull);
    });

    test('the meter is relative: the same bitrate is loud in one room and '
        'quiet in another', () {
      final quietRoom = AudioLevelTracker();
      _feed(quietRoom, _quietBps, 30);
      final inQuietRoom = _feed(quietRoom, 40000, 3);

      final noisyRoom = AudioLevelTracker();
      _feed(noisyRoom, 40000, 30);
      final inNoisyRoom = _feed(noisyRoom, 40000, 3);

      expect(inQuietRoom, greaterThan(0.5));
      expect(inNoisyRoom, closeTo(0.0, 1e-6));
    });

    test('span self-calibrates between min and max clamps', () {
      final t = AudioLevelTracker();
      _feed(t, _quietBps, 30);
      expect(t.spanDb, kMinSpanDb, reason: 'flat signal → min span');
      _feed(t, _loudBps, 12);
      expect(t.spanDb, closeTo(12.0, 0.2),
          reason: 'ceiling learned the +12 dB burst');
      // A +40 dB burst caps at the max span.
      _feed(t, _quietBps * 10000, 12);
      expect(t.spanDb, kMaxSpanDb);
    });

    test('once the span widens, a moderate sound reads as moderate', () {
      final t = AudioLevelTracker();
      _feed(t, _quietBps, 30);
      _feed(t, _loudBps, 12); // learn a 12 dB ceiling
      _feed(t, _quietBps, 5); // settle back down
      // +6 dB (4× bitrate) over a 12 dB span ≈ 0.5.
      final level = _feed(t, _quietBps * 4, 5);
      expect(level, closeTo(0.5, 0.05));
    });

    test('level rises immediately and decays with the release constant', () {
      final t = AudioLevelTracker();
      _feed(t, _quietBps, 30);
      // Attack: within two ticks of a burst the meter is most of the way up.
      _tick(t, _loudBps);
      final afterOneTick =
          _tick(t, _loudBps);
      expect(afterOneTick, greaterThan(0.8));
      _feed(t, _loudBps, 3);
      expect(t.level, closeTo(1.0, 1e-6));

      // Release: back to quiet, the level falls but does not snap to zero.
      final oneTickLater =
          _tick(t, _quietBps);
      expect(oneTickLater, lessThan(1.0));
      expect(oneTickLater, greaterThan(0.3));
      // After a few seconds it has decayed away.
      final later = _feed(t, _quietBps, 4);
      expect(later, lessThan(0.02));
    });

    test('release is monotonic — no bounce on the way down', () {
      final t = AudioLevelTracker();
      _feed(t, _quietBps, 30);
      _feed(t, _loudBps, 3);
      var prev = t.level;
      for (var i = 0; i < 16; i++) {
        final next = _tick(t, _quietBps);
        expect(next, lessThanOrEqualTo(prev));
        prev = next;
      }
    });

    test('a stalled stream (not flowing) decays to zero and leaves the floor',
        () {
      final t = AudioLevelTracker();
      _feed(t, _quietBps, 30);
      _feed(t, _loudBps, 3);
      final floorBefore = t.floorDb;
      // A stale loud bitrate must not keep the meter lit while nothing flows.
      final level = _feed(t, _loudBps, 5, flowing: false);
      expect(level, lessThan(0.01));
      expect(t.floorDb, floorBefore);
    });

    test('flowing with no bitrate yet holds the previous level', () {
      final t = AudioLevelTracker();
      _feed(t, _quietBps, 30);
      _feed(t, _loudBps, 3);
      final held = _feed(t, null, 2);
      expect(held, closeTo(1.0, 1e-6));
    });

    test('garbage bitrate never throws and never yields NaN', () {
      final t = AudioLevelTracker();
      _feed(t, _quietBps, 30);
      for (final bad in [double.nan, double.infinity, -1.0, 0.0]) {
        final level = _tick(t, bad);
        expect(level.isFinite, isTrue);
        expect(level, inInclusiveRange(0.0, 1.0));
      }
      for (final badDb in [double.nan, double.infinity, double.negativeInfinity]) {
        final level = t.update(db: badDb, flowing: true, dtSeconds: _dt);
        expect(level.isFinite, isTrue);
        expect(level, inInclusiveRange(0.0, 1.0));
      }
      final level = t.update(
          db: bitrateToDb(_quietBps), flowing: true, dtSeconds: double.nan);
      expect(level.isFinite, isTrue);
    });

    test('the floor forgets a quiet dip once it leaves the window', () {
      final t = AudioLevelTracker(calibrationWindowSeconds: 20);
      _feed(t, _quietBps, 10); // quiet baseline
      _feed(t, _quietBps * 4, 30); // +6 dB steady for longer than the window
      // Old quiet samples have aged out, so the new steady state is the floor
      // and the level has settled back to zero.
      expect(t.floorDb!, closeTo(bitrateToDb(_quietBps * 4)!, 0.1));
      expect(t.level, closeTo(0.0, 0.02));
    });

    test('a single jittery packet does not lower the floor', () {
      final t = AudioLevelTracker();
      _feed(t, _quietBps, 30);
      final floorBefore = t.floorDb!;
      _tick(t, _quietBps / 100);
      _feed(t, _quietBps, 5);
      // The 2 s calibration smoothing keeps one -20 dB outlier from
      // dragging the floor down with it.
      expect(t.floorDb!, greaterThan(floorBefore - 3.0));
    });
  });
}
