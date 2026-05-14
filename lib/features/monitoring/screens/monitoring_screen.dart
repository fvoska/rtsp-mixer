import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/logging/app_logger.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/foreground_service.dart';
import '../../../core/theme/spacing.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/audio_player_provider.dart';
import '../providers/session_history_provider.dart';
import '../services/audio_handler.dart';
import '../widgets/camera_audio_card.dart';

class MonitoringScreen extends ConsumerStatefulWidget {
  const MonitoringScreen({super.key});

  @override
  ConsumerState<MonitoringScreen> createState() => _MonitoringScreenState();
}

class _MonitoringScreenState extends ConsumerState<MonitoringScreen>
    with WidgetsBindingObserver {
  /// Global video toggle (app bar button).
  bool _globalVideo = false;

  /// Border highlight sensitivity. 0.0 = most sensitive, 1.0 = least.
  double _activityThreshold = 0.05;

  /// Per-camera video overrides. If absent, follows _globalVideo.
  final Map<String, bool> _perCameraVideo = {};

  bool _videoSuspendedByLifecycle = false;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future.microtask(() async {
      // Request notification permission (required on Android 13+)
      final notifPerm = await FlutterForegroundTask.checkNotificationPermission();
      if (notifPerm != NotificationPermission.granted) {
        appLog('FGS', 'Requesting notification permission');
        await FlutterForegroundTask.requestNotificationPermission();
      }
      // Request battery optimization exemption for overnight reliability
      if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
        appLog('FGS', 'Requesting battery optimization exemption');
        await FlutterForegroundTask.requestIgnoreBatteryOptimization();
      }

      // Cameras are already loaded by AuthNotifier before we get here.
      // startMonitoring is idempotent (260514-siv) — safe to call when the
      // ShellRoute re-mounts MonitoringScreen for any reason.
      await ref.read(audioPlayerProvider.notifier).startMonitoring();
      // Start foreground service after monitoring is active
      final monState = ref.read(audioPlayerProvider).value;
      if (monState != null && monState.cameras.isNotEmpty) {
        final names = monState.cameras.map((c) => c.cameraName).toList();
        await ForegroundServiceManager.start(names);
        // Remember monitoring state for auto-resume on app restart
        await ref.read(storageProvider).write('was_monitoring', 'true');

        // Initialize audio_service for MediaSession lock screen controls (D-04)
        try {
          final handler = await ref.read(audioHandlerProvider.future);
          handler.setCameraNames(names);
          handler.setPlaying();
        } catch (e) {
          // audio_service is nice-to-have -- don't break monitoring if it fails
          appLog('AUDIO_SERVICE', 'Failed to init audio handler: $e');
        }
      }
    });
  }

  @override
  void dispose() {
    _disposed = true;
    appLog('UI', 'MonitoringScreen disposing');
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }


  bool _isVideoOn(String cameraId) =>
      _perCameraVideo[cameraId] ?? _globalVideo;

  bool get _anyVideoOn =>
      _globalVideo || _perCameraVideo.values.any((v) => v);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_disposed) return;
    // D-06: Video preview auto-disables when app is backgrounded or screen turns off.
    // Re-enables when user returns. Audio continues uninterrupted.
    try {
      final notifier = ref.read(audioPlayerProvider.notifier);
      if (state == AppLifecycleState.inactive ||
          state == AppLifecycleState.hidden ||
          state == AppLifecycleState.paused) {
        if (_anyVideoOn) {
          appLog('LIFECYCLE', 'App backgrounded — disabling video preview (D-06)');
          _videoSuspendedByLifecycle = true;
          notifier.setVideoEnabled(false);
        }
      } else if (state == AppLifecycleState.resumed) {
        if (_videoSuspendedByLifecycle) {
          appLog('LIFECYCLE', 'App resumed — re-enabling video preview (D-06)');
          _videoSuspendedByLifecycle = false;
          _restoreVideoState();
        }
      }
    } catch (e) {
      appLog('LIFECYCLE', 'Error toggling video on lifecycle change: $e');
    }
  }

  /// Re-apply the per-camera video state after lifecycle resume.
  void _restoreVideoState() {
    final notifier = ref.read(audioPlayerProvider.notifier);
    final cameras = ref.read(audioPlayerProvider).value?.cameras ?? [];
    for (final cam in cameras) {
      notifier.setVideoEnabledForCamera(cam.cameraId, _isVideoOn(cam.cameraId));
    }
  }

  void _toggleGlobalVideo() {
    final notifier = ref.read(audioPlayerProvider.notifier);
    setState(() {
      _globalVideo = !_globalVideo;
      _perCameraVideo.clear();
    });
    appLog('UI', 'Global video ${_globalVideo ? "on" : "off"}');
    notifier.setVideoEnabled(_globalVideo);
  }

  void _toggleCameraVideo(String cameraId) {
    final notifier = ref.read(audioPlayerProvider.notifier);
    setState(() {
      final current = _isVideoOn(cameraId);
      _perCameraVideo[cameraId] = !current;
    });
    appLog('UI', 'Camera $cameraId video ${_isVideoOn(cameraId) ? "on" : "off"}');
    notifier.setVideoEnabledForCamera(cameraId, _isVideoOn(cameraId));
  }

  Future<void> _onStopPressed() async {
    await ref.read(storageProvider).delete('was_monitoring');
    await ref.read(audioPlayerProvider.notifier).stopMonitoring();
    await ForegroundServiceManager.stop();
    if (mounted) context.go('/cameras');
  }

  @override
  Widget build(BuildContext context) {
    final monitoringState = ref.watch(audioPlayerProvider);
    final sessionHistory = ref.watch(sessionHistoryProvider).value;
    final hasCameras = monitoringState.value?.cameras.isNotEmpty ?? false;
    final hasCurrentSession = sessionHistory?.current != null;
    final showStopFab = hasCameras && hasCurrentSession;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Monitoring'),
        actions: [
          IconButton(
            icon: Icon(_globalVideo ? Icons.videocam : Icons.videocam_off),
            tooltip: _globalVideo
                ? 'Hide all video previews'
                : 'Show all video previews',
            onPressed: _toggleGlobalVideo,
          ),
        ],
      ),
      body: monitoringState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (state) {
          final debugMode = ref.watch(settingsProvider).debugMode;
          if (state.cameras.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.all(Spacing.lg),
            child: Column(
              children: [
                for (int i = 0; i < state.cameras.length; i++) ...[
                  CameraAudioCard(
                    cameraState: state.cameras[i],
                    cameraIndex: i,
                    showVideoPreview: _isVideoOn(state.cameras[i].cameraId),
                    showDebugInfo: debugMode,
                    activityThreshold: _activityThreshold,
                    onToggleVideo: () =>
                        _toggleCameraVideo(state.cameras[i].cameraId),
                  ),
                  if (i < state.cameras.length - 1)
                    const SizedBox(height: Spacing.lg),
                ],
                // Sensitivity slider (debug mode only)
                if (debugMode) ...[
                  const SizedBox(height: Spacing.lg),
                  Row(
                    children: [
                      Text('Activity trigger',
                          style: Theme.of(context).textTheme.bodySmall),
                      Expanded(
                        child: Slider(
                          value: _activityThreshold,
                          min: 0.01,
                          max: 0.5,
                          onChanged: (v) =>
                              setState(() => _activityThreshold = v),
                        ),
                      ),
                      SizedBox(
                        width: 48,
                        child: Text(
                          _activityThreshold < 0.05
                              ? 'High'
                              : _activityThreshold < 0.15
                                  ? 'Med'
                                  : 'Low',
                          style: Theme.of(context).textTheme.bodySmall,
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ],
                  ),
                ],
                // Leave room below the FAB so the last card isn't covered.
                if (showStopFab) const SizedBox(height: 80),
              ],
            ),
          );
        },
      ),
      floatingActionButton: showStopFab
          ? FloatingActionButton.extended(
              onPressed: _onStopPressed,
              backgroundColor: theme.colorScheme.errorContainer,
              foregroundColor: theme.colorScheme.onErrorContainer,
              icon: const Icon(Icons.stop_rounded),
              label: const Text('Stop monitoring'),
            )
          : null,
    );
  }
}
