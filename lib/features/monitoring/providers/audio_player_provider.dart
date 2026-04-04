import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../../core/logging/app_logger.dart';
import '../../../core/services/foreground_service.dart';
import '../../cameras/providers/camera_provider.dart';
import '../models/player_state.dart';

final audioPlayerProvider =
    AsyncNotifierProvider<AudioPlayerNotifier, MonitoringState>(
        AudioPlayerNotifier.new);

class AudioPlayerNotifier extends AsyncNotifier<MonitoringState> {
  final Map<String, Player> _players = {};
  final Map<String, VideoController> _videoControllers = {};
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  Timer? _levelPollTimer;
  final Map<String, double> _lastAudioPts = {};
  final Map<String, double> _baselineLevel = {};
  String _lastNotificationText = '';

  @override
  Future<MonitoringState> build() async {
    ref.onDispose(() {
      _levelPollTimer?.cancel();
      for (final sub in _subscriptions) {
        sub.cancel();
      }
      _subscriptions.clear();
      _videoControllers.clear();
      for (final p in _players.values) {
        p.dispose();
      }
      _players.clear();
      _lastAudioPts.clear();
      _baselineLevel.clear();
    });
    return const MonitoringState();
  }

  /// Expose players for video preview widgets.
  Player? getPlayer(String cameraId) => _players[cameraId];

  /// Get the VideoController for a camera (created at player init time).
  VideoController? getVideoController(String cameraId) =>
      _videoControllers[cameraId];

  int _cameraIndex(String cameraId) {
    final current = state.value;
    if (current == null) return -1;
    return current.cameras.indexWhere((c) => c.cameraId == cameraId);
  }

  void _updateStreamInfo(String cameraId, StreamInfo Function(StreamInfo) updater) {
    final current = state.value;
    if (current == null) return;
    final idx = _cameraIndex(cameraId);
    if (idx < 0) return;
    final cam = current.cameras[idx];
    state = AsyncData(current.copyWithCamera(idx, cam.copyWith(
      streamInfo: updater(cam.streamInfo),
    )));
  }

  void _listenToPlayer(Player player, String cameraName, String cameraId) {
    _subscriptions.add(
      player.stream.playing.listen((playing) {
        appLog('STREAM', '$cameraName playing=$playing');
      }),
    );
    _subscriptions.add(
      player.stream.completed.listen((completed) {
        appLog('STREAM', '$cameraName completed=$completed');
      }),
    );
    _subscriptions.add(
      player.stream.error.listen((error) {
        appLog('STREAM', '$cameraName error=$error');
      }),
    );
    _subscriptions.add(
      player.stream.buffering.listen((buffering) {
        appLog('STREAM', '$cameraName buffering=$buffering');
        // Update status based on buffering state.
        final current = state.value;
        if (current == null) return;
        final idx = _cameraIndex(cameraId);
        if (idx < 0) return;
        final cam = current.cameras[idx];
        if (buffering && cam.connectionStatus == CameraConnectionStatus.playing) {
          state = AsyncData(current.copyWithCamera(idx,
            cam.copyWith(connectionStatus: CameraConnectionStatus.connecting)));
        } else if (!buffering && cam.connectionStatus == CameraConnectionStatus.connecting) {
          state = AsyncData(current.copyWithCamera(idx,
            cam.copyWith(connectionStatus: CameraConnectionStatus.playing)));
        }
      }),
    );
    _subscriptions.add(
      player.stream.audioParams.listen((params) {
        appLog('STREAM', '$cameraName audioParams=$params');
        _updateStreamInfo(cameraId, (info) => info.merge(
          sampleRate: params.sampleRate,
          channels: params.hrChannels,
        ));
      }),
    );
    _subscriptions.add(
      player.stream.track.listen((track) {
        appLog('STREAM', '$cameraName track: audio=${track.audio} video=${track.video}');
        final a = track.audio;
        final v = track.video;
        _updateStreamInfo(cameraId, (info) => info.merge(
          audioCodec: a.codec,
          audioBitrate: a.bitrate,
          videoCodec: v.codec,
          videoBitrate: v.bitrate,
          width: v.w,
          height: v.h,
          fps: v.fps,
        ));
      }),
    );
    _subscriptions.add(
      player.stream.log.listen((log) {
        // Suppress noisy HEVC/H264 decoder errors from mid-stream joins.
        if (log.prefix.contains('ffmpeg/video') &&
            (log.text.contains('PPS id out of range') ||
             log.text.contains('SPS id out of range') ||
             log.text.contains('non-existing PPS') ||
             log.text.contains('decode_slice_header') ||
             log.text.contains('no frame'))) {
          return;
        }
        appLog('MPV', '$cameraName [${log.prefix}] ${log.level}: ${log.text}');
      }),
    );
  }

  Player _createPlayer() => Player(
        configuration: const PlayerConfiguration(
          protocolWhitelist: [
            'udp', 'rtp', 'tcp', 'tls', 'data', 'file',
            'http', 'https', 'crypto', 'rtsp', 'rtsps',
          ],
          bufferSize: 2 * 1024 * 1024,
        ),
      );

  Future<void> startMonitoring({bool videoPreview = false}) async {
    final cameraState = ref.read(cameraNotifierProvider).value;
    final selectedCameras = cameraState?.selectedCameras ?? [];
    if (selectedCameras.isEmpty) {
      appLog('AUDIO', 'Cannot start monitoring: no cameras selected');
      return;
    }

    state = const AsyncLoading();
    appLog('AUDIO', 'Starting monitoring for ${selectedCameras.length} cameras (video=$videoPreview)');

    final cameraStates = <CameraAudioState>[];

    for (final camera in selectedCameras) {
      final cameraName = camera.name ?? 'Camera';
      appLog('AUDIO', 'Connecting to $cameraName (${camera.id})');

      final quality = camera.defaultQuality;
      final url = camera.defaultStreamUrl;

      var camState = CameraAudioState(
        cameraId: camera.id,
        cameraName: cameraName,
        connectionStatus: CameraConnectionStatus.connecting,
        availableQualities: camera.rtspsStreamUrls,
        activeQuality: quality,
        activeStreamUrl: url,
        mac: camera.mac,
        modelKey: camera.modelKey,
        micVolume: camera.micVolume,
      );

      if (!camera.isMicEnabled) {
        camState = camState.copyWith(
          errorMessage:
              'Microphone is disabled on this camera -- enable it in Protect camera settings',
        );
        appLog('AUDIO', 'Warning: mic disabled on $cameraName');
      }

      try {
        if (url == null || url.isEmpty) {
          throw StateError('No RTSPS URL for $cameraName — enable RTSP in Protect camera settings');
        }

        final player = _createPlayer();
        final nativePlayer = player.platform as NativePlayer;
        await nativePlayer.setProperty('profile', 'low-latency');
        await nativePlayer.setProperty('cache', 'no');
        await nativePlayer.setProperty('demuxer-lavf-o', 'rtsp_transport=tcp');

        // Create VideoController BEFORE open so the render context exists.
        // This is required for vid=auto to work later.
        _videoControllers[camera.id] = VideoController(player);

        _players[camera.id] = player;
        _listenToPlayer(player, cameraName, camera.id);

        appLog('AUDIO', 'Opening stream ($quality): $url');
        await player.open(Media(url));

        // Disable video after open if not previewing (audio-only mode).
        if (!videoPreview) {
          await nativePlayer.setProperty('vid', 'no');
        }


        camState = camState.copyWith(
          connectionStatus: CameraConnectionStatus.playing,
        );
        appLog('AUDIO', '$cameraName is now playing');
      } catch (e) {
        appLog('AUDIO', 'Error connecting to $cameraName: $e');
        camState = camState.copyWith(
          connectionStatus: CameraConnectionStatus.error,
          errorMessage: e.toString(),
        );
      }

      cameraStates.add(camState);
    }

    state = AsyncData(MonitoringState(cameras: cameraStates));
    appLog('AUDIO', 'Monitoring started for ${cameraStates.length} cameras');

    // Update foreground notification with camera status
    try {
      final statusParts = cameraStates.map((c) {
        final status = c.connectionStatus == CameraConnectionStatus.playing
            ? '' : ' (${c.connectionStatus.name})';
        return '${c.cameraName}$status';
      }).toList();
      final text = 'Monitoring: ${statusParts.join(", ")}';
      _lastNotificationText = text;
      await ForegroundServiceManager.updateNotification(text: text);
    } catch (e) {
      appLog('FGS', 'Failed to update notification: $e');
    }

    // Start polling audio-pts to detect silence / estimate activity.
    _startLevelPolling();
  }

  static const _pollInterval = Duration(milliseconds: 500);

  void _startLevelPolling() {
    _levelPollTimer?.cancel();
    _levelPollTimer = Timer.periodic(_pollInterval, (_) => _pollAudioLevels());
  }

  Future<void> _pollAudioLevels() async {
    final current = state.value;
    if (current == null || current.cameras.isEmpty) return;

    var changed = false;
    var updated = current;

    for (int i = 0; i < updated.cameras.length; i++) {
      final cam = updated.cameras[i];
      if (!cam.isLive) continue;

      final player = _players[cam.cameraId];
      if (player == null) continue;

      try {
        final np = player.platform as NativePlayer;

        // Audio PTS: tracks whether audio data is flowing per-player.
        // Not a loudness measurement, but reliably detects silence vs activity.
        final ptsStr = await np.getProperty('audio-pts');
        final pts = double.tryParse(ptsStr) ?? 0.0;
        final lastPts = _lastAudioPts[cam.cameraId] ?? 0.0;
        final ptsDelta = pts - lastPts;
        _lastAudioPts[cam.cameraId] = pts;

        final flowing = ptsDelta > 0.01;
        // Normalize: typical delta at 500ms poll is ~0.5s.
        final level = flowing ? (ptsDelta / 0.6).clamp(0.2, 1.0) : 0.0;

        // Activity: deviation from per-camera baseline.
        final prevBaseline = _baselineLevel[cam.cameraId] ?? level;
        final baseline = prevBaseline * 0.95 + level * 0.05;
        _baselineLevel[cam.cameraId] = baseline;
        final rawActivity = (level - baseline).clamp(0.0, 1.0);
        final prevActivity = cam.audioActivity;
        final activity = rawActivity > prevActivity
            ? rawActivity
            : prevActivity * 0.7;

        final newSilence = !flowing
            ? cam.silenceDuration + _pollInterval.inMilliseconds / 1000.0
            : 0.0;

        // Poll mpv properties for stream metadata (track events are sparse for RTSP).
        final audioCodec = await _tryGetProperty(np, 'audio-codec-name');
        final videoCodec = await _tryGetProperty(np, 'video-codec-name');
        final audioFormat = await _tryGetProperty(np, 'audio-params/format');
        final audioSampleRate = int.tryParse(await _tryGetProperty(np, 'audio-params/samplerate') ?? '');
        final audioChannelCount = int.tryParse(await _tryGetProperty(np, 'audio-params/channel-count') ?? '');
        final audioChannels = await _tryGetProperty(np, 'audio-params/hr-channels');
        final width = int.tryParse(await _tryGetProperty(np, 'video-params/w') ?? '');
        final height = int.tryParse(await _tryGetProperty(np, 'video-params/h') ?? '');
        final fps = double.tryParse(await _tryGetProperty(np, 'container-fps') ?? '');
        final audioBitrate = double.tryParse(await _tryGetProperty(np, 'audio-bitrate') ?? '');
        final videoBitrate = double.tryParse(await _tryGetProperty(np, 'video-bitrate') ?? '');

        final newInfo = cam.streamInfo.merge(
          audioCodec: audioCodec,
          videoCodec: videoCodec,
          sampleRate: audioSampleRate,
          channels: audioChannels ?? (audioChannelCount != null ? '${audioChannelCount}ch' : null),
          audioBitrate: audioBitrate?.round(),
          videoBitrate: videoBitrate?.round(),
          width: width,
          height: height,
          fps: fps,
          audioFormat: audioFormat,
        );

        final infoChanged = newInfo.audioCodec != cam.streamInfo.audioCodec ||
            newInfo.videoCodec != cam.streamInfo.videoCodec ||
            newInfo.sampleRate != cam.streamInfo.sampleRate ||
            newInfo.width != cam.streamInfo.width ||
            newInfo.audioBitrate != cam.streamInfo.audioBitrate ||
            newInfo.videoBitrate != cam.streamInfo.videoBitrate;

        if ((level - cam.audioLevel).abs() > 0.05 ||
            (activity - cam.audioActivity).abs() > 0.03 ||
            (newSilence - cam.silenceDuration).abs() > 0.5 ||
            infoChanged) {
          updated = updated.copyWithCamera(
            i,
            cam.copyWith(
              audioLevel: level,
              audioActivity: activity,
              silenceDuration: newSilence,
              streamInfo: newInfo,
            ),
          );
          changed = true;
        }
      } catch (_) {
        // Player may be disposed during poll.
      }
    }

    if (changed) {
      state = AsyncData(updated);

      // Update notification if status text changed
      try {
        final statusParts = updated.cameras.map((c) {
          final status = c.connectionStatus == CameraConnectionStatus.playing
              ? '' : ' (${c.connectionStatus.name})';
          return '${c.cameraName}$status';
        }).toList();
        final newText = 'Monitoring: ${statusParts.join(", ")}';
        if (newText != _lastNotificationText) {
          _lastNotificationText = newText;
          ForegroundServiceManager.updateNotification(text: newText);
        }
      } catch (_) {}
    }
  }

  Future<String?> _tryGetProperty(NativePlayer np, String name) async {
    try {
      final v = await np.getProperty(name);
      return v.isEmpty ? null : v;
    } catch (_) {
      return null;
    }
  }

  void setVolume(int cameraIndex, double volume) {
    final current = state.value;
    if (current == null) return;
    if (cameraIndex < 0 || cameraIndex >= current.cameras.length) return;

    final camState = current.cameras[cameraIndex];
    final player = _players[camState.cameraId];
    if (player == null) return;

    player.setVolume(camState.isMuted ? 0.0 : volume);
    appLog('AUDIO', '${camState.cameraName} volume=${volume.toStringAsFixed(0)}');

    state = AsyncData(
      current.copyWithCamera(
        cameraIndex,
        camState.copyWith(volume: volume, preMuteVolume: volume),
      ),
    );
  }

  void toggleMute(int cameraIndex) {
    final current = state.value;
    if (current == null) return;
    if (cameraIndex < 0 || cameraIndex >= current.cameras.length) return;

    final camState = current.cameras[cameraIndex];
    final player = _players[camState.cameraId];
    if (player == null) return;

    if (camState.isMuted) {
      player.setVolume(camState.preMuteVolume);
      appLog('AUDIO', '${camState.cameraName} unmuted (vol=${camState.preMuteVolume.toStringAsFixed(0)})');
      state = AsyncData(
        current.copyWithCamera(
          cameraIndex,
          camState.copyWith(isMuted: false),
        ),
      );
    } else {
      player.setVolume(0.0);
      appLog('AUDIO', '${camState.cameraName} muted');
      state = AsyncData(
        current.copyWithCamera(
          cameraIndex,
          camState.copyWith(
            isMuted: true,
            preMuteVolume: camState.volume,
          ),
        ),
      );
    }
  }

  /// Enable or disable video decoding on all active players.
  Future<void> setVideoEnabled(bool enabled) async {
    final value = enabled ? 'auto' : 'no';
    appLog('AUDIO', 'Setting vid=$value on ${_players.length} players');
    _setAllCamerasConnecting();
    for (final player in _players.values) {
      final nativePlayer = player.platform as NativePlayer;
      await nativePlayer.setProperty('vid', value);
    }
    // Restore playing status directly — toggling vid track may not trigger
    // a buffering event since the audio stream is already flowing.
    _restoreAllCamerasPlaying();
  }

  void _setAllCamerasConnecting() {
    final current = state.value;
    if (current == null) return;
    var updated = current;
    for (int i = 0; i < updated.cameras.length; i++) {
      if (updated.cameras[i].isLive) {
        updated = updated.copyWithCamera(i,
          updated.cameras[i].copyWith(connectionStatus: CameraConnectionStatus.connecting));
      }
    }
    state = AsyncData(updated);
  }

  void _restoreAllCamerasPlaying() {
    final current = state.value;
    if (current == null) return;
    var updated = current;
    for (int i = 0; i < updated.cameras.length; i++) {
      if (updated.cameras[i].connectionStatus == CameraConnectionStatus.connecting) {
        updated = updated.copyWithCamera(i,
          updated.cameras[i].copyWith(connectionStatus: CameraConnectionStatus.playing));
      }
    }
    state = AsyncData(updated);
  }

  /// Switch stream quality for a camera. Stops and re-opens with the new URL.
  Future<void> switchQuality(int cameraIndex, String quality) async {
    final current = state.value;
    if (current == null) return;
    if (cameraIndex < 0 || cameraIndex >= current.cameras.length) return;

    final camState = current.cameras[cameraIndex];
    final url = camState.availableQualities[quality];
    if (url == null || url == camState.activeStreamUrl) return;

    final player = _players[camState.cameraId];
    if (player == null) return;

    appLog('AUDIO', 'Switching ${camState.cameraName} to $quality: $url');

    state = AsyncData(current.copyWithCamera(
      cameraIndex,
      camState.copyWith(
        connectionStatus: CameraConnectionStatus.connecting,
        activeQuality: quality,
        activeStreamUrl: url,
      ),
    ));

    try {
      await player.open(Media(url));
      final updated = state.value!;
      state = AsyncData(updated.copyWithCamera(
        cameraIndex,
        updated.cameras[cameraIndex].copyWith(
          connectionStatus: CameraConnectionStatus.playing,
        ),
      ));
      appLog('AUDIO', '${camState.cameraName} now playing $quality');
    } catch (e) {
      appLog('AUDIO', 'Error switching quality: $e');
      final updated = state.value!;
      state = AsyncData(updated.copyWithCamera(
        cameraIndex,
        updated.cameras[cameraIndex].copyWith(
          connectionStatus: CameraConnectionStatus.error,
          errorMessage: e.toString(),
        ),
      ));
    }
  }

  /// Enable or disable video decoding on a single player by camera ID.
  Future<void> setVideoEnabledForCamera(String cameraId, bool enabled) async {
    final player = _players[cameraId];
    if (player == null) return;
    final value = enabled ? 'auto' : 'no';
    appLog('AUDIO', 'Setting vid=$value for camera $cameraId');
    final nativePlayer = player.platform as NativePlayer;
    await nativePlayer.setProperty('vid', value);
  }

  Future<void> stopMonitoring() async {
    appLog('AUDIO', 'Stopping monitoring');
    _levelPollTimer?.cancel();
    _lastAudioPts.clear();
    _baselineLevel.clear();
    _lastNotificationText = '';
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
    _videoControllers.clear();
    for (final player in _players.values) {
      await player.stop();
      await player.dispose();
    }
    _players.clear();
    state = const AsyncData(MonitoringState());
    appLog('AUDIO', 'All players stopped and disposed');
  }
}
