import 'dart:typed_data';

import '../peer_protocol.dart';

/// Build a 44-byte RIFF/WAVE header for an endless PCM stream.
///
/// The RIFF and `data` chunk sizes are set to 0xFFFFFFFF: FFmpeg's WAV
/// demuxer treats that as "unknown length / streaming", which is exactly what
/// libmpv needs to play a live HTTP source without seeking or an EOF.
Uint8List wavStreamHeader({
  int sampleRate = kPeerSampleRate,
  int channels = kPeerChannels,
  int bitsPerSample = kPeerBitsPerSample,
}) {
  final blockAlign = channels * (bitsPerSample ~/ 8);
  final byteRate = sampleRate * blockAlign;
  final bytes = ByteData(44);
  void ascii(int offset, String s) {
    for (var i = 0; i < s.length; i++) {
      bytes.setUint8(offset + i, s.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  bytes.setUint32(4, 0xFFFFFFFF, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  bytes.setUint32(16, 16, Endian.little); // PCM fmt chunk size
  bytes.setUint16(20, 1, Endian.little); // WAVE_FORMAT_PCM
  bytes.setUint16(22, channels, Endian.little);
  bytes.setUint32(24, sampleRate, Endian.little);
  bytes.setUint32(28, byteRate, Endian.little);
  bytes.setUint16(32, blockAlign, Endian.little);
  bytes.setUint16(34, bitsPerSample, Endian.little);
  ascii(36, 'data');
  bytes.setUint32(40, 0xFFFFFFFF, Endian.little);
  return bytes.buffer.asUint8List();
}
