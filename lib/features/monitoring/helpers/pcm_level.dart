import 'dart:math' as math;
import 'dart:typed_data';

/// Pure-Dart loudness measurement of raw PCM.
///
/// The PCM tap asks mpv for signed 16-bit little-endian mono at 8 kHz
/// (`audio-format=s16`, `audio-channels=mono`, `audio-samplerate=8000`):
/// 16 KB/s, plenty for a level meter. This file turns those bytes into a
/// dBFS reading. It is pure math over plain Dart values — no I/O, no native
/// code — so it is unit-testable and can never throw out of the poll loop.

/// Sample rate the tap requests from mpv.
const kPcmSampleRate = 8000;

/// Bytes per sample for s16 mono.
const kPcmBytesPerSample = 2;

/// Length of the short-term RMS window. A crying baby's bursts are tens of
/// milliseconds apart; 50 ms windows resolve them while still averaging
/// over enough samples (400) for a stable reading.
const kPcmWindowMs = 50;

/// Samples per short-term window.
const kPcmWindowSamples = kPcmSampleRate * kPcmWindowMs ~/ 1000;

/// Lowest level reported. Digital silence would be -∞ dBFS; clamping keeps
/// every downstream subtraction finite.
const kPcmSilenceDbfs = -90.0;

/// Converts a stream of s16-LE mono PCM bytes into a per-tick loudness in
/// dBFS (0 dBFS = full scale).
///
/// [measure] is called once per poll tick with whatever bytes arrived since
/// the previous call. It splits them into 50 ms windows, computes the RMS of
/// each, and reports the LOUDEST window in dBFS — the short-term peak RMS,
/// which is what a VU-style meter wants: a 100 ms shriek inside an
/// otherwise quiet quarter-second must register, not be averaged away.
///
/// Bytes that do not fill a whole window are carried over to the next call
/// (including a dangling odd byte), so no sample is ever dropped or
/// mis-aligned across ticks.
class PcmLevelMeter {
  PcmLevelMeter({this.windowSamples = kPcmWindowSamples});

  final int windowSamples;

  /// Leftover bytes from the previous call that did not complete a window.
  Uint8List _carry = Uint8List(0);

  /// Feed [bytes] and return the loudest 50 ms window in dBFS, or null when
  /// fewer than one full window has accumulated.
  double? measure(Uint8List bytes) {
    try {
      final data = _carry.isEmpty ? bytes : _concat(_carry, bytes);
      final windowBytes = windowSamples * kPcmBytesPerSample;
      final whole = (data.length ~/ windowBytes) * windowBytes;
      _carry = whole < data.length
          ? Uint8List.fromList(data.sublist(whole))
          : Uint8List(0);
      if (whole == 0) return null;

      final view = ByteData.sublistView(data, 0, whole);
      var loudest = 0.0;
      for (var start = 0; start < whole; start += windowBytes) {
        var sumSquares = 0.0;
        for (var i = 0; i < windowBytes; i += kPcmBytesPerSample) {
          final s = view.getInt16(start + i, Endian.little).toDouble();
          sumSquares += s * s;
        }
        final rms = math.sqrt(sumSquares / windowSamples);
        if (rms > loudest) loudest = rms;
      }
      return rmsToDbfs(loudest);
    } catch (_) {
      // Malformed input must not kill the poll loop: report nothing.
      _carry = Uint8List(0);
      return null;
    }
  }

  /// Drop any carried-over partial window (e.g. when the tap restarts).
  void reset() => _carry = Uint8List(0);

  static Uint8List _concat(Uint8List a, Uint8List b) {
    final out = Uint8List(a.length + b.length);
    out.setRange(0, a.length, a);
    out.setRange(a.length, out.length, b);
    return out;
  }
}

/// RMS amplitude (0..32767) to dBFS, clamped at [kPcmSilenceDbfs]. Never
/// returns NaN or -∞.
double rmsToDbfs(double rms) {
  if (!rms.isFinite || rms <= 0) return kPcmSilenceDbfs;
  final db = 20.0 * math.log(rms / 32768.0) / math.ln10;
  if (!db.isFinite) return kPcmSilenceDbfs;
  return math.max(kPcmSilenceDbfs, db);
}
