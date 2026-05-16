import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/logging/app_logger.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/foreground_service.dart';
import '../../../core/theme/spacing.dart';
import '../../auth/providers/auth_provider.dart';
import '../../cameras/providers/camera_provider.dart';
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
  /// Global video toggle.
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
    final authState = ref.watch(authNotifierProvider).value;
    // Stop control visibility depends on whether a session exists OR the auth
    // layer is signalling a monitoring resume. hasCameras is intentionally not
    // part of this predicate: on relaunch (was_monitoring=true) and during the
    // camera-fetch window of startMonitoring, cameras may briefly be empty even
    // though the user has an active session they need to be able to stop.
    final hasCurrentSession = sessionHistory?.current != null ||
        (authState?.resumeMonitoring ?? false);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Monitoring'),
      ),
      body: Column(
        children: [
          if (hasCurrentSession)
            _InlineStopBanner(onStop: _onStopPressed),
          Expanded(
            child: monitoringState.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (state) {
                final debugMode = ref.watch(settingsProvider).debugMode;
                if (state.cameras.isEmpty) {
                  // Two reasons this branch fires:
                  //   1. No cameras selected yet — show a CTA to /cameras.
                  //   2. Cameras are selected but haven't connected yet — spinner.
                  final selected =
                      ref.watch(cameraNotifierProvider).value?.selectedCameras ??
                          const [];
                  if (selected.isEmpty) {
                    return const _NoCamerasSelected();
                  }
                  return const Center(child: CircularProgressIndicator());
                }
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(Spacing.lg),
                  child: Column(
                    children: [
                      _VideoToggleRow(
                        globalVideoOn: _globalVideo,
                        onToggle: _toggleGlobalVideo,
                      ),
                      const SizedBox(height: Spacing.md),
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
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Sticky red banner at the top of the monitoring body that lets the user stop
/// the session at any time — including the relaunch window where audio is
/// resuming but cameras haven't reloaded yet. Mirrors the visual language of
/// [ActiveSessionBar] so the control feels the same on every tab.
class _InlineStopBanner extends StatelessWidget {
  const _InlineStopBanner({required this.onStop});

  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.errorContainer,
      child: SafeArea(
        top: false,
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.lg,
            vertical: Spacing.sm,
          ),
          child: Row(
            children: [
              Icon(
                Icons.fiber_manual_record,
                size: 12,
                color: theme.colorScheme.onErrorContainer,
              ),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: Text(
                  'Monitoring active',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: onStop,
                style: FilledButton.styleFrom(
                  backgroundColor: theme.colorScheme.onErrorContainer,
                  foregroundColor: theme.colorScheme.errorContainer,
                ),
                icon: const Icon(Icons.stop_rounded),
                label: const Text('Stop'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VideoToggleRow extends StatelessWidget {
  const _VideoToggleRow({
    required this.globalVideoOn,
    required this.onToggle,
  });

  final bool globalVideoOn;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            'Cameras',
            style: theme.textTheme.titleMedium,
          ),
        ),
        TextButton.icon(
          onPressed: onToggle,
          icon: Icon(globalVideoOn ? Icons.videocam : Icons.videocam_off),
          label: Text(globalVideoOn ? 'Hide video' : 'Show video'),
        ),
      ],
    );
  }
}

class _NoCamerasSelected extends StatelessWidget {
  const _NoCamerasSelected();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Spacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.videocam_off_outlined,
              size: 64,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: Spacing.lg),
            Text(
              'No cameras selected',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: Spacing.sm),
            Text(
              'Pick the cameras you want to listen to. You can change them anytime.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Spacing.xl),
            FilledButton.icon(
              icon: const Icon(Icons.videocam),
              label: const Text('Select cameras'),
              onPressed: () => context.push('/cameras'),
            ),
          ],
        ),
      ),
    );
  }
}
