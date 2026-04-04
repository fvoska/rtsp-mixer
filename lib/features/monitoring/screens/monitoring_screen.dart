import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/logging/app_logger.dart';
import '../../../core/services/foreground_service.dart';
import '../../../core/theme/spacing.dart';
import '../../auth/providers/auth_provider.dart';
import '../../cameras/providers/camera_provider.dart';
import '../providers/audio_player_provider.dart';
import '../services/audio_handler.dart';
import '../widgets/camera_audio_card.dart';
import '../widgets/stop_monitoring_button.dart';

class MonitoringScreen extends ConsumerStatefulWidget {
  const MonitoringScreen({super.key});

  @override
  ConsumerState<MonitoringScreen> createState() => _MonitoringScreenState();
}

class _MonitoringScreenState extends ConsumerState<MonitoringScreen>
    with WidgetsBindingObserver {
  /// Global video toggle (app bar button).
  bool _globalVideo = false;

  /// Show debug/stream info in cards.
  bool _showDebugInfo = false;

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
    FlutterForegroundTask.addTaskDataCallback(_receiveTaskData);
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

      // Wait for cameras with RTSPS URLs (cache may load without URLs,
      // background API refresh adds them shortly after)
      appLog('AUDIO', 'Waiting for cameras with RTSPS URLs...');
      await Future.doWhile(() async {
        await Future.delayed(const Duration(milliseconds: 100));
        if (_disposed) return false;
        final prov = ref.read(cameraNotifierProvider);
        if (prov.hasError) return false;
        final selected = prov.value?.selectedCameras ?? [];
        if (selected.isEmpty) return true; // still loading
        return selected.any((c) => c.defaultStreamUrl == null);
      });
      if (_disposed) return;

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
    FlutterForegroundTask.removeTaskDataCallback(_receiveTaskData);
    WidgetsBinding.instance.removeObserver(this);
    // Stop service and players fire-and-forget — state updates will be ignored
    // since _disposed is true and the widget is defunct.
    ForegroundServiceManager.stop();
    ref.read(audioPlayerProvider.notifier).stopMonitoring();
    super.dispose();
  }

  void _receiveTaskData(Object data) {
    if (_disposed) return;
    if (data is Map) {
      final action = data['action'];
      if (action == 'toggle') {
        // D-04: play/pause toggle — mute/unmute all cameras
        appLog('FGS', 'Received toggle action from notification');
        try {
          final notifier = ref.read(audioPlayerProvider.notifier);
          final state = ref.read(audioPlayerProvider).value;
          if (state != null) {
            // If any camera is unmuted, mute all (pause). Otherwise unmute all (play).
            final anyUnmuted = state.cameras.any((c) => !c.isMuted);
            for (int i = 0; i < state.cameras.length; i++) {
              if (anyUnmuted && !state.cameras[i].isMuted) {
                notifier.toggleMute(i);
              } else if (!anyUnmuted && state.cameras[i].isMuted) {
                notifier.toggleMute(i);
              }
            }
          }
        } catch (e) {
          appLog('FGS', 'Error handling toggle: $e');
        }
      } else if (action == 'stop') {
        appLog('FGS', 'Received stop action from foreground service');
        _stopAndGoBack();
      }
    }
  }

  Future<void> _stopAndGoBack() async {
    if (_disposed) return;
    _disposed = true;
    await ref.read(storageProvider).delete('was_monitoring');
    await ref.read(audioPlayerProvider.notifier).stopMonitoring();
    // Stop audio_service MediaSession
    try {
      final handler = await ref.read(audioHandlerProvider.future);
      handler.setIdle();
    } catch (e) {
      appLog('AUDIO_SERVICE', 'Failed to stop audio handler: $e');
    }
    await ForegroundServiceManager.stop();
    if (mounted) {
      context.go('/cameras');
    }
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

  void _openLogs() {
    context.push('/logs');
  }

  @override
  Widget build(BuildContext context) {
    final monitoringState = ref.watch(audioPlayerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Monitoring'),
        actions: [
          IconButton(
            icon: Icon(_showDebugInfo ? Icons.bug_report : Icons.bug_report_outlined),
            tooltip: _showDebugInfo ? 'Hide stream info' : 'Show stream info',
            onPressed: () => setState(() => _showDebugInfo = !_showDebugInfo),
          ),
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
                    showDebugInfo: _showDebugInfo,
                    activityThreshold: _activityThreshold,
                    onToggleVideo: () =>
                        _toggleCameraVideo(state.cameras[i].cameraId),
                  ),
                  if (i < state.cameras.length - 1)
                    const SizedBox(height: Spacing.lg),
                ],
                // Sensitivity slider (debug mode only)
                if (_showDebugInfo) ...[
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
                  const SizedBox(height: Spacing.sm),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.terminal, size: 18),
                      label: const Text('View logs'),
                      onPressed: _openLogs,
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
      bottomNavigationBar: const StopMonitoringButton(),
    );
  }
}
