import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rtsp_mixer/features/monitoring/helpers/pcm_level.dart';

/// s16-LE mono PCM of [samples].
Uint8List _pcm(List<int> samples) {
  final data = ByteData(samples.length * 2);
  for (var i = 0; i < samples.length; i++) {
    data.setInt16(i * 2, samples[i], Endian.little);
  }
  return data.buffer.asUint8List();
}

/// A full-scale-relative sine at [amplitude] (0..1) for [n] samples.
List<int> _sine(int n, double amplitude, {double freq = 440}) =>
    List<int>.generate(
      n,
      (i) => (math.sin(2 * math.pi * freq * i / kPcmSampleRate) *
              amplitude *
              32767)
          .round(),
    );

void main() {
  group('rmsToDbfs', () {
    test('full scale is 0 dBFS, half scale is -6 dB', () {
      expect(rmsToDbfs(32768), closeTo(0.0, 1e-9));
      expect(rmsToDbfs(16384), closeTo(-6.02, 0.01));
    });

    test('silence and garbage clamp to the floor, never NaN', () {
      expect(rmsToDbfs(0), kPcmSilenceDbfs);
      expect(rmsToDbfs(-1), kPcmSilenceDbfs);
      expect(rmsToDbfs(double.nan), kPcmSilenceDbfs);
      expect(rmsToDbfs(1e-9), kPcmSilenceDbfs);
    });
  });

  group('PcmLevelMeter', () {
    test('window is 50 ms of 8 kHz audio', () {
      expect(kPcmWindowSamples, 400);
    });

    test('a full-scale sine reads about -3 dBFS (sine RMS = peak/√2)', () {
      final m = PcmLevelMeter();
      final db = m.measure(_pcm(_sine(kPcmWindowSamples * 4, 1.0)));
      expect(db, isNotNull);
      expect(db!, closeTo(-3.01, 0.1));
    });

    test('digital silence reads the floor', () {
      final m = PcmLevelMeter();
      final db = m.measure(_pcm(List.filled(kPcmWindowSamples * 2, 0)));
      expect(db, kPcmSilenceDbfs);
    });

    test('reports the LOUDEST window in the tick, not the average', () {
      final m = PcmLevelMeter();
      // Three quiet windows and one loud one.
      final samples = [
        ..._sine(kPcmWindowSamples * 3, 0.01),
        ..._sine(kPcmWindowSamples, 0.5),
      ];
      final db = m.measure(_pcm(samples))!;
      // 0.5 amplitude sine → -6 dB peak, -9 dB RMS.
      expect(db, closeTo(-9.03, 0.2));
    });

    test('returns null until a whole window has accumulated, then carries '
        'the remainder across calls', () {
      final m = PcmLevelMeter();
      final loud = _sine(kPcmWindowSamples, 0.5);
      final bytes = _pcm(loud);
      // Feed in three uneven pieces, the first two too short for a window.
      expect(m.measure(bytes.sublist(0, 301)), isNull); // odd byte count
      expect(m.measure(bytes.sublist(301, 500)), isNull);
      final db = m.measure(bytes.sublist(500));
      expect(db, isNotNull);
      expect(db!, closeTo(-9.03, 0.2));
    });

    test('reset drops a partial window', () {
      final m = PcmLevelMeter();
      m.measure(_pcm(_sine(100, 0.5)));
      m.reset();
      // 300 more samples would complete the window without the reset.
      expect(m.measure(_pcm(_sine(300, 0.5))), isNull);
    });

    test('empty input is fine', () {
      expect(PcmLevelMeter().measure(Uint8List(0)), isNull);
    });
  });
}
