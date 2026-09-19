import 'dart:typed_data';

import 'package:record/record.dart';

import '../../../core/logging/app_logger.dart';
import '../peer_protocol.dart';

/// Source of PCM16 audio for host mode. Abstract so tests (and a future
/// desktop line-in) can inject a fake stream; the real one wraps the
/// `record` plugin's microphone stream.
abstract class AudioCaptureSource {
  /// Check — and, when [request] is set, ask for — microphone permission.
  Future<bool> hasPermission({bool request = true});

  /// Start capturing in the [kPeerSampleRate]/[kPeerChannels]/PCM16 format.
  /// The returned stream ends (or errors) if the platform tears the
  /// recorder down; the owner restarts it.
  Future<Stream<Uint8List>> start();

  Future<void> stop();

  Future<void> dispose();
}

class MicrophoneCapture implements AudioCaptureSource {
  AudioRecorder? _recorder;

  AudioRecorder get _rec => _recorder ??= AudioRecorder();

  @override
  Future<bool> hasPermission({bool request = true}) async {
    try {
      return await _rec.hasPermission(request: request);
    } catch (e) {
      appLog('MIC', 'hasPermission failed: $e');
      return false;
    }
  }

  @override
  Future<Stream<Uint8List>> start() async {
    return _rec.startStream(const RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: kPeerSampleRate,
      numChannels: kPeerChannels,
      // A baby monitor wants the raw room, not a phone-call-tuned signal:
      // no gain riding that would flatten a cry against a quiet room, and
      // no noise suppression that might learn a fan and then a whimper.
      autoGain: false,
      echoCancel: false,
      noiseSuppress: false,
      androidConfig: AndroidRecordConfig(
        audioSource: AndroidAudioSource.mic,
        // Never grab a Bluetooth headset's mic — the phone is the room mic.
        manageBluetooth: false,
      ),
    ));
  }

  @override
  Future<void> stop() async {
    try {
      await _recorder?.stop();
    } catch (e) {
      appLog('MIC', 'stop failed (ignored): $e');
    }
  }

  @override
  Future<void> dispose() async {
    try {
      await _recorder?.dispose();
    } catch (e) {
      appLog('MIC', 'dispose failed (ignored): $e');
    }
    _recorder = null;
  }
}
