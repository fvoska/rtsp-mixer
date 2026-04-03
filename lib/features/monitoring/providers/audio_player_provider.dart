import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import '../../../core/logging/app_logger.dart';
import '../../auth/providers/auth_provider.dart';
import '../../cameras/providers/camera_provider.dart';
import '../helpers/pan_filter.dart';
import '../helpers/rtsp_url.dart';
import '../models/player_state.dart';

final audioPlayerProvider =
    AsyncNotifierProvider<AudioPlayerNotifier, MonitoringState>(
        AudioPlayerNotifier.new);

class AudioPlayerNotifier extends AsyncNotifier<MonitoringState> {
  final Map<String, Player> _players = {};

  @override
  Future<MonitoringState> build() async {
    ref.onDispose(() {
      for (final p in _players.values) {
        p.dispose();
      }
      _players.clear();
    });
    return const MonitoringState();
  }

  Future<void> startMonitoring() async {
    final authState = ref.read(authNotifierProvider).value;
    final host = authState?.host;
    if (host == null) {
      appLog('AUDIO', 'Cannot start monitoring: no host');
      return;
    }

    final cameraState = ref.read(cameraNotifierProvider).value;
    final selectedCameras = cameraState?.selectedCameras ?? [];
    if (selectedCameras.isEmpty) {
      appLog('AUDIO', 'Cannot start monitoring: no cameras selected');
      return;
    }

    state = const AsyncLoading();
    appLog('AUDIO', 'Starting monitoring for ${selectedCameras.length} cameras');

    final cameraStates = <CameraAudioState>[];

    for (final camera in selectedCameras) {
      final cameraName = camera.name ?? 'Camera';
      appLog('AUDIO', 'Connecting to $cameraName (${camera.id})');

      var camState = CameraAudioState(
        cameraId: camera.id,
        cameraName: cameraName,
        connectionStatus: CameraConnectionStatus.connecting,
      );

      if (!camera.isMicEnabled) {
        camState = camState.copyWith(
          errorMessage:
              'Microphone is disabled on this camera -- enable it in Protect camera settings',
        );
        appLog('AUDIO', 'Warning: mic disabled on $cameraName');
      }

      try {
        final player = Player(
          configuration: const PlayerConfiguration(
            protocolWhitelist: [
              'udp',
              'rtp',
              'tcp',
              'tls',
              'data',
              'file',
              'http',
              'https',
              'crypto',
              'rtsp',
              'rtsps',
            ],
            bufferSize: 2 * 1024 * 1024,
          ),
        );

        final nativePlayer = player.platform as NativePlayer;
        await nativePlayer.setProperty('vid', 'no');
        await nativePlayer.setProperty('profile', 'low-latency');
        await nativePlayer.setProperty('cache', 'no');
        await nativePlayer.setProperty('demuxer-lavf-o', 'rtsp_transport=tcp');

        _players[camera.id] = player;

        final url = rtspUrl(host, camera.id);
        appLog('AUDIO', 'Opening stream: $url');
        await player.open(Media(url));

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
  }

  void setVolume(int cameraIndex, double volume) {
    final current = state.value;
    if (current == null) return;
    if (cameraIndex < 0 || cameraIndex >= current.cameras.length) return;

    final camState = current.cameras[cameraIndex];
    final player = _players[camState.cameraId];
    if (player == null) return;

    player.setVolume(camState.isMuted ? 0.0 : volume);

    state = AsyncData(
      current.copyWithCamera(
        cameraIndex,
        camState.copyWith(volume: volume, preMuteVolume: volume),
      ),
    );
  }

  Future<void> setPan(int cameraIndex, double pan) async {
    final current = state.value;
    if (current == null) return;
    if (cameraIndex < 0 || cameraIndex >= current.cameras.length) return;

    final camState = current.cameras[cameraIndex];
    final player = _players[camState.cameraId];
    if (player == null) return;

    final nativePlayer = player.platform as NativePlayer;
    await nativePlayer.setProperty('af', buildPanFilter(pan));

    state = AsyncData(
      current.copyWithCamera(
        cameraIndex,
        camState.copyWith(pan: pan),
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
      state = AsyncData(
        current.copyWithCamera(
          cameraIndex,
          camState.copyWith(isMuted: false),
        ),
      );
    } else {
      player.setVolume(0.0);
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

  Future<void> stopMonitoring() async {
    appLog('AUDIO', 'Stopping monitoring');
    for (final player in _players.values) {
      await player.stop();
      await player.dispose();
    }
    _players.clear();
    state = const AsyncData(MonitoringState());
    appLog('AUDIO', 'All players stopped and disposed');
  }
}
