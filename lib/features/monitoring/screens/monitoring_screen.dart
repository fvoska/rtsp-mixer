import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/logging/app_logger.dart';
import '../../../core/services/foreground_service.dart';
import '../../../core/theme/spacing.dart';
import '../providers/audio_player_provider.dart';
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    FlutterForegroundTask.addTaskDataCallback(_receiveTaskData);
    Future.microtask(() async {
      await ref.read(audioPlayerProvider.notifier).startMonitoring();
      // Start foreground service after monitoring is active
      final monState = ref.read(audioPlayerProvider).value;
      if (monState != null && monState.cameras.isNotEmpty) {
        final names = monState.cameras.map((c) => c.cameraName).toList();
        await ForegroundServiceManager.start(names);
      }
    });
  }

  @override
  void dispose() {
    FlutterForegroundTask.removeTaskDataCallback(_receiveTaskData);
    WidgetsBinding.instance.removeObserver(this);
    // Prevent zombie foreground service if user navigates away without pressing Stop
    ref.read(audioPlayerProvider.notifier).stopMonitoring();
    ForegroundServiceManager.stop();
    super.dispose();
  }

  void _receiveTaskData(Object data) {
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
    await ref.read(audioPlayerProvider.notifier).stopMonitoring();
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
      // Clear per-camera overrides so everything follows the global toggle.
      _perCameraVideo.clear();
    });
    notifier.setVideoEnabled(_globalVideo);
  }

  void _toggleCameraVideo(String cameraId) {
    final notifier = ref.read(audioPlayerProvider.notifier);
    setState(() {
      final current = _isVideoOn(cameraId);
      _perCameraVideo[cameraId] = !current;
    });
    notifier.setVideoEnabledForCamera(cameraId, _isVideoOn(cameraId));
  }

  void _exportLogs() {
    final logs = AppLogger.instance.exportFromDisk;
    Clipboard.setData(ClipboardData(text: logs));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Logs copied to clipboard')),
    );
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
                      icon: const Icon(Icons.share, size: 18),
                      label: const Text('Export logs'),
                      onPressed: _exportLogs,
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
