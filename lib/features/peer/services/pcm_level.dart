import 'dart:math' as math;
import 'dart:typed_data';

/// Loudness of a PCM16 little-endian chunk as a 0..1 level.
///
/// RMS in dBFS mapped linearly from [floorDb] (→ 0.0) to 0 dBFS (→ 1.0).
/// -60 dBFS is a quiet room on a phone mic; the mapping is fixed so the host
/// meter and the monitor's card mean the same thing. Odd trailing bytes,
/// empty input, NaN — all return 0.0, never throw (this runs on every mic
/// chunk inside the host's capture stream).
double pcm16Level(Uint8List bytes, {double floorDb = -60.0}) {
  try {
    final samples = bytes.lengthInBytes ~/ 2;
    if (samples == 0) return 0.0;
    final data = ByteData.sublistView(bytes, 0, samples * 2);
    var sumSq = 0.0;
    for (var i = 0; i < samples; i++) {
      final s = data.getInt16(i * 2, Endian.little) / 32768.0;
      sumSq += s * s;
    }
    final rms = math.sqrt(sumSq / samples);
    if (rms <= 0 || !rms.isFinite) return 0.0;
    final db = 20 * math.log(rms) / math.ln10;
    final level = (db - floorDb) / (0 - floorDb);
    if (level.isNaN) return 0.0;
    return level.clamp(0.0, 1.0);
  } catch (_) {
    return 0.0;
  }
}
