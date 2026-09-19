import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rtsp_mixer/features/peer/services/pcm_level.dart';
import 'package:rtsp_mixer/features/peer/services/wav_stream.dart';

Uint8List _sine(double amplitude, {int samples = 1600}) {
  final data = ByteData(samples * 2);
  for (var i = 0; i < samples; i++) {
    final v = (amplitude * 32767 * math.sin(2 * math.pi * i / 40)).round();
    data.setInt16(i * 2, v, Endian.little);
  }
  return data.buffer.asUint8List();
}

void main() {
  group('wavStreamHeader', () {
    test('is a 44-byte PCM header with streaming sizes', () {
      final h = wavStreamHeader(sampleRate: 16000, channels: 1);
      expect(h.length, 44);
      expect(String.fromCharCodes(h.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(h.sublist(8, 12)), 'WAVE');
      expect(String.fromCharCodes(h.sublist(12, 16)), 'fmt ');
      expect(String.fromCharCodes(h.sublist(36, 40)), 'data');
      final bd = ByteData.sublistView(h);
      expect(bd.getUint32(4, Endian.little), 0xFFFFFFFF);
      expect(bd.getUint32(40, Endian.little), 0xFFFFFFFF);
      expect(bd.getUint16(20, Endian.little), 1); // PCM
      expect(bd.getUint16(22, Endian.little), 1); // mono
      expect(bd.getUint32(24, Endian.little), 16000);
      expect(bd.getUint32(28, Endian.little), 32000); // byte rate
      expect(bd.getUint16(32, Endian.little), 2); // block align
      expect(bd.getUint16(34, Endian.little), 16);
    });
  });

  group('pcm16Level', () {
    test('silence is 0 and full-scale is 1', () {
      expect(pcm16Level(Uint8List(3200)), 0.0);
      // A full-scale sine has RMS -3 dBFS → ~0.95 on a -60 dB floor.
      expect(pcm16Level(_sine(1.0)), closeTo(0.95, 0.01));
    });

    test('quieter input yields a lower level, monotonic', () {
      final loud = pcm16Level(_sine(0.5));
      final quiet = pcm16Level(_sine(0.01));
      expect(loud, greaterThan(quiet));
      expect(quiet, greaterThan(0.0));
    });

    test('tolerates odd byte counts and empty input', () {
      expect(pcm16Level(Uint8List(0)), 0.0);
      expect(pcm16Level(Uint8List.fromList([0x12])), 0.0);
      expect(() => pcm16Level(Uint8List.fromList([1, 2, 3])), returnsNormally);
    });
  });
}
