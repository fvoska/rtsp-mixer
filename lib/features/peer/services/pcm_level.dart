import 'dart:math' as math;
import 'dart:typed_data';

/// Floor for [pcm16Dbfs]: digital silence would be -∞, so it is clamped.
const kPeerSilenceDbfs = -90.0;

/// RMS loudness of a PCM16 little-endian chunk in dBFS (0 = full scale),
/// clamped at [kPeerSilenceDbfs]. This is what the host reports on its
/// status endpoint so a monitor can feed it to the same noise-floor tracker
/// its PCM tap uses. Odd trailing bytes, empty input, NaN — all return the
/// silence floor, never throw (this runs on every mic chunk).
double pcm16Dbfs(Uint8List bytes) {
  try {
    final samples = bytes.lengthInBytes ~/ 2;
    if (samples == 0) return kPeerSilenceDbfs;
    final data = ByteData.sublistView(bytes, 0, samples * 2);
    var sumSq = 0.0;
    for (var i = 0; i < samples; i++) {
      final s = data.getInt16(i * 2, Endian.little) / 32768.0;
      sumSq += s * s;
    }
    final rms = math.sqrt(sumSq / samples);
    if (rms <= 0 || !rms.isFinite) return kPeerSilenceDbfs;
    final db = 20 * math.log(rms) / math.ln10;
    if (!db.isFinite) return kPeerSilenceDbfs;
    return math.max(kPeerSilenceDbfs, db);
  } catch (_) {
    return kPeerSilenceDbfs;
  }
}

/// Loudness of a PCM16 little-endian chunk as a 0..1 level for the host's
/// own on-screen meter: [pcm16Dbfs] mapped linearly from [floorDb] (→ 0.0)
/// to 0 dBFS (→ 1.0). -60 dBFS is a quiet room on a phone mic. Never throws.
double pcm16Level(Uint8List bytes, {double floorDb = -60.0}) =>
    dbfsToLevel(pcm16Dbfs(bytes), floorDb: floorDb);

/// Linear dBFS → 0..1 mapping shared by the host meter. Never NaN.
double dbfsToLevel(double db, {double floorDb = -60.0}) {
  if (!db.isFinite) return 0.0;
  final level = (db - floorDb) / (0 - floorDb);
  if (level.isNaN) return 0.0;
  return level.clamp(0.0, 1.0);
}
