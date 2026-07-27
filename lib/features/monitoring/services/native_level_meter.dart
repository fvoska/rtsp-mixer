import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../../core/logging/app_logger.dart';

/// Dart face of the Android level-meter sidecar
/// (`levelmeter/LevelMeterController.kt`).
///
/// The sidecar opens a second, audio-only RTSP session per camera with a
/// native decoder and streams real PCM levels (RMS/peak dBFS) back over an
/// EventChannel — the loudness signal the mpv playback path cannot provide
/// (no PCM tap in libmpv, no analysis filters in its stripped FFmpeg).
///
/// Everything here is best-effort by contract (CLAUDE.md): on any platform
/// without the native side (desktop, web) or on any channel failure, methods
/// log and return false so callers fall back to the bitrate proxy. Nothing
/// throws into the monitoring pipeline.
class NativeLevelMeter {
  static const MethodChannel _channel = MethodChannel('roomtone/level_meter');
  static const EventChannel _eventChannel =
      EventChannel('roomtone/level_meter/events');

  /// The sidecar is implemented only on Android — the product platform.
  /// Desktop dev builds keep the bitrate proxy.
  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Broadcast stream of parsed sidecar events. Unparseable events are
  /// dropped, channel errors are logged and swallowed — the stream never
  /// errors into a listener.
  Stream<NativeLevelEvent> events() => _eventChannel
      .receiveBroadcastStream()
      .map(nativeLevelEventFromDynamic)
      .handleError(
          (Object e) => appLog('METER', 'event stream error (ignored): $e'))
      .where((e) => e != null)
      .cast<NativeLevelEvent>();

  /// Replace all running analyzers with one per entry. Returns false when
  /// the native side is unavailable or the call failed.
  Future<bool> start(List<({String id, List<String> urls})> cameras) async {
    if (!isSupported) return false;
    try {
      await _channel.invokeMethod<Object?>('start', {
        'cameras': [
          for (final cam in cameras) {'id': cam.id, 'urls': cam.urls},
        ],
      });
      return true;
    } catch (e) {
      appLog('METER', 'native start failed (bitrate fallback): $e');
      return false;
    }
  }

  /// Start (or replace) the analyzer for a single camera.
  Future<bool> startCamera(String id, List<String> urls) async {
    if (!isSupported) return false;
    try {
      await _channel
          .invokeMethod<Object?>('startCamera', {'id': id, 'urls': urls});
      return true;
    } catch (e) {
      appLog('METER', 'native startCamera($id) failed: $e');
      return false;
    }
  }

  Future<void> stopCamera(String id) async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<Object?>('stopCamera', {'id': id});
    } catch (e) {
      appLog('METER', 'native stopCamera($id) failed (ignored): $e');
    }
  }

  Future<void> stopAll() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<Object?>('stopAll');
    } catch (e) {
      appLog('METER', 'native stopAll failed (ignored): $e');
    }
  }
}

/// One event from the native sidecar. `type` is either `level` (rmsDb/peakDb
/// set) or `status` (state/detail set).
class NativeLevelEvent {
  final String type;
  final String cameraId;
  final double? rmsDb;
  final double? peakDb;
  final String? state;
  final String? detail;

  const NativeLevelEvent({
    required this.type,
    required this.cameraId,
    this.rmsDb,
    this.peakDb,
    this.state,
    this.detail,
  });

  bool get isLevel => type == 'level';
}

/// Parse a raw platform-channel event into a [NativeLevelEvent].
///
/// Pure and total: any shape mismatch (wrong types, missing keys, non-finite
/// numbers) returns null instead of throwing — events originate from native
/// code and must never be able to break the monitoring pipeline.
NativeLevelEvent? nativeLevelEventFromDynamic(Object? raw) {
  try {
    if (raw is! Map) return null;
    final type = raw['type'];
    final cameraId = raw['cameraId'];
    if (type is! String || cameraId is! String || cameraId.isEmpty) {
      return null;
    }
    double? asFiniteDouble(Object? v) {
      if (v is! num) return null;
      final d = v.toDouble();
      return d.isFinite ? d : null;
    }

    switch (type) {
      case 'level':
        final rms = asFiniteDouble(raw['rmsDb']);
        if (rms == null) return null;
        return NativeLevelEvent(
          type: type,
          cameraId: cameraId,
          rmsDb: rms,
          peakDb: asFiniteDouble(raw['peakDb']),
        );
      case 'status':
        return NativeLevelEvent(
          type: type,
          cameraId: cameraId,
          state: raw['state'] is String ? raw['state'] as String : null,
          detail: raw['detail'] is String ? raw['detail'] as String : null,
        );
      default:
        return null;
    }
  } catch (_) {
    return null;
  }
}
