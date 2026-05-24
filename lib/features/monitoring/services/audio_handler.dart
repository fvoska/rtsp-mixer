import 'dart:io' show Platform;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/logging/app_logger.dart';
import '../providers/audio_player_provider.dart';

/// Minimal AudioHandler that provides MediaSession integration for
/// lock screen play/pause/stop controls (per D-04).
///
/// This bridges audio_service's MediaSession to the existing
/// AudioPlayerNotifier. It does NOT manage players directly.
class MonitoringAudioHandler extends BaseAudioHandler {
  final Ref _ref;

  MonitoringAudioHandler(this._ref);

  /// Update the media notification metadata with camera names.
  void setCameraNames(List<String> cameraNames) {
    mediaItem.add(MediaItem(
      id: 'baby_monitor',
      title: 'Baby Monitor Active',
      artist: 'Monitoring: ${cameraNames.join(", ")}',
      album: 'RTSP Mixer',
    ));
  }

  /// Mark playback as active -- shows pause button on lock screen.
  void setPlaying() {
    playbackState.add(playbackState.value.copyWith(
      playing: true,
      controls: [MediaControl.pause, MediaControl.stop],
      processingState: AudioProcessingState.ready,
    ));
  }

  /// Mark playback as idle -- hides media notification.
  void setIdle() {
    playbackState.add(playbackState.value.copyWith(
      playing: false,
      processingState: AudioProcessingState.idle,
      controls: [],
    ));
  }

  @override
  Future<void> play() async {
    appLog('AUDIO_SERVICE', 'MediaSession play');
    // Resume: unmute all cameras
    try {
      final notifier = _ref.read(audioPlayerProvider.notifier);
      final state = _ref.read(audioPlayerProvider).value;
      if (state != null) {
        for (int i = 0; i < state.cameras.length; i++) {
          if (state.cameras[i].isMuted) {
            notifier.toggleMute(i);
          }
        }
      }
    } catch (e) {
      appLog('AUDIO_SERVICE', 'Error in play: $e');
    }
    setPlaying();
  }

  @override
  Future<void> pause() async {
    appLog('AUDIO_SERVICE', 'MediaSession pause');
    // Pause: mute all cameras (don't stop streams -- per D-04 play/pause toggle)
    try {
      final notifier = _ref.read(audioPlayerProvider.notifier);
      final state = _ref.read(audioPlayerProvider).value;
      if (state != null) {
        for (int i = 0; i < state.cameras.length; i++) {
          if (!state.cameras[i].isMuted) {
            notifier.toggleMute(i);
          }
        }
      }
    } catch (e) {
      appLog('AUDIO_SERVICE', 'Error in pause: $e');
    }
    playbackState.add(playbackState.value.copyWith(
      playing: false,
      controls: [MediaControl.play, MediaControl.stop],
    ));
  }

  @override
  Future<void> stop() async {
    appLog('AUDIO_SERVICE', 'MediaSession stop');
    // Full cleanup so the user's expectation matches the label: Stop ends
    // monitoring everywhere — deletes was_monitoring, clears the resume
    // flag, tears down players, and stops the foreground service. Without
    // this the inline banner / mini-bar stay visible after the media-
    // notification Stop, which made it look like the button did nothing.
    try {
      await _ref.read(audioPlayerProvider.notifier).stopMonitoringAndCleanup();
    } catch (e) {
      appLog('AUDIO_SERVICE', 'Error in stop: $e');
    }
    setIdle();
    await super.stop();
  }
}

/// Riverpod provider for the AudioHandler. Initialized once.
/// Usage: final handler = await ref.read(audioHandlerProvider.future);
///
/// On non-Android platforms (Windows desktop, etc.) the MediaSession layer
/// is unsupported — the handler is returned without calling
/// `AudioService.init`. Its public methods (`setCameraNames`, `setPlaying`,
/// `setIdle`, `play`, `pause`, `stop`) all push to the inherited streams
/// from `BaseAudioHandler`, which is safe without platform init.
final audioHandlerProvider = FutureProvider<MonitoringAudioHandler>((ref) async {
  final handler = MonitoringAudioHandler(ref);
  if (kIsWeb || !Platform.isAndroid) {
    appLog('AUDIO_SERVICE',
        'MediaSession unsupported on this platform — skipping AudioService.init');
    return handler;
  }
  await AudioService.init(
    builder: () => handler,
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'baby_monitor_media',
      androidNotificationChannelName: 'Baby Monitor Media',
      androidNotificationOngoing: false,
      androidStopForegroundOnPause: true,
    ),
  );
  return handler;
});
