import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/logging/app_logger.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/foreground_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/spacing.dart';
import '../../auth/providers/auth_provider.dart';
import '../../cameras/providers/camera_provider.dart';
import '../models/player_state.dart';
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

  /// Whether to show extra per-camera debug detail (replaces the old global
  /// debug-mode setting — this lives per-screen-session only).
  bool _showDetails = false;

  /// Per-camera video overrides. If absent, follows _globalVideo.
  final Map<String, bool> _perCameraVideo = {};

  bool _videoSuspendedByLifecycle = false;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future.microtask(_maybeAutoResume);
  }

  /// Only auto-start monitoring on mount if the auth layer signals that the
  /// previous session should be resumed (was_monitoring=true on disk). The
  /// idle Monitor tab is now a first-class state where the user explicitly
  /// taps Start — we don't want every tab switch back to Monitor to silently
  /// reconnect streams.
  Future<void> _maybeAutoResume() async {
    // Notification + battery permissions — fine to request on every mount,
    // they're idempotent on the platform side. Skip entirely on non-Android
    // platforms (Windows desktop, etc.) since FlutterForegroundTask has no
    // implementation there. Per CLAUDE.md "Defensive error handling":
    // wrap in try/catch even inside the platform guard.
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final notifPerm =
            await FlutterForegroundTask.checkNotificationPermission();
        if (notifPerm != NotificationPermission.granted) {
          appLog('FGS', 'Requesting notification permission');
          await FlutterForegroundTask.requestNotificationPermission();
        }
        if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
          appLog('FGS', 'Requesting battery optimization exemption');
          await FlutterForegroundTask.requestIgnoreBatteryOptimization();
        }
      } catch (e) {
        appLog('FGS', 'Permission request failed (continuing): $e');
      }
    }

    final resume = ref.read(authNotifierProvider).value?.resumeMonitoring ?? false;
    if (!resume) {
      appLog('UI', 'Monitor tab mounted with no resume flag — staying idle');
      return;
    }
    await _startMonitoringFlow();
  }

  /// Begin monitoring with the current camera selection. Used by both
  /// the explicit Start button and the auto-resume path.
  Future<void> _startMonitoringFlow() async {
    await ref.read(audioPlayerProvider.notifier).startMonitoring();
    final monState = ref.read(audioPlayerProvider).value;
    if (monState != null && monState.cameras.isNotEmpty) {
      final names = monState.cameras.map((c) => c.cameraName).toList();
      await ForegroundServiceManager.start(names);
      await ref.read(storageProvider).write('was_monitoring', 'true');
      try {
        final handler = await ref.read(audioHandlerProvider.future);
        handler.setCameraNames(names);
        handler.setPlaying();
      } catch (e) {
        appLog('AUDIO_SERVICE', 'Failed to init audio handler: $e');
      }
    }
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
    await ref.read(audioPlayerProvider.notifier).stopMonitoringAndCleanup();
    // Intentionally no navigation — the Monitor tab now handles the idle
    // state (camera picker) so the user can pick + restart without leaving.
  }

  Future<void> _onRemoveCamera(String cameraId) async {
    await ref.read(audioPlayerProvider.notifier).removeCamera(cameraId);
    _perCameraVideo.remove(cameraId);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final monitoringState = ref.watch(audioPlayerProvider);
    final sessionHistory = ref.watch(sessionHistoryProvider).value;
    final authState = ref.watch(authNotifierProvider).value;
    final hasCurrentSession = sessionHistory?.current != null ||
        (authState?.resumeMonitoring ?? false);

    return Scaffold(
      appBar: AppBar(title: const Text('Monitoring')),
      body: Column(
        children: [
          if (hasCurrentSession)
            _InlineStopBanner(
              status: _resolveBannerStatus(monitoringState),
              onStop: _onStopPressed,
            ),
          Expanded(
            child: hasCurrentSession
                ? _LiveMonitoringView(
                    monitoringState: monitoringState,
                    globalVideo: _globalVideo,
                    showDetails: _showDetails,
                    onToggleGlobalVideo: _toggleGlobalVideo,
                    onToggleShowDetails: () =>
                        setState(() => _showDetails = !_showDetails),
                    isVideoOn: _isVideoOn,
                    onToggleCameraVideo: _toggleCameraVideo,
                    onRemoveCamera: _onRemoveCamera,
                  )
                : _IdleCameraPicker(onStart: _startMonitoringFlow),
          ),
        ],
      ),
    );
  }
}

/// Health status for the sticky monitoring banner. Drives banner color so a
/// glance gives the user honest feedback (green = streaming, blue =
/// connecting / reconnecting, red = error) rather than always reading as
/// "error" the way a hard-coded red bar did.
enum _BannerStatus { playing, connecting, error }

_BannerStatus _resolveBannerStatus(AsyncValue<MonitoringState> async) {
  if (async.hasError) return _BannerStatus.error;
  final state = async.value;
  if (state == null || state.cameras.isEmpty) return _BannerStatus.connecting;
  if (state.anyError) return _BannerStatus.error;
  if (state.allLive) return _BannerStatus.playing;
  return _BannerStatus.connecting;
}

/// Sticky banner at the top of the monitoring body that lets the user stop
/// the session at any time. Color reflects current stream health.
class _InlineStopBanner extends StatelessWidget {
  const _InlineStopBanner({required this.status, required this.onStop});

  final _BannerStatus status;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final background = switch (status) {
      _BannerStatus.playing => AppTheme.statusOnline,
      _BannerStatus.connecting => AppTheme.statusConnecting,
      _BannerStatus.error => AppTheme.statusOffline,
    };
    const foreground = Colors.black87;
    return Material(
      color: background,
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
              const Icon(
                Icons.fiber_manual_record,
                size: 12,
                color: foreground,
              ),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: Text(
                  'Monitoring active',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: foreground,
                  ),
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: onStop,
                style: FilledButton.styleFrom(
                  backgroundColor: foreground,
                  foregroundColor: background,
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

class _LiveMonitoringView extends ConsumerWidget {
  const _LiveMonitoringView({
    required this.monitoringState,
    required this.globalVideo,
    required this.showDetails,
    required this.onToggleGlobalVideo,
    required this.onToggleShowDetails,
    required this.isVideoOn,
    required this.onToggleCameraVideo,
    required this.onRemoveCamera,
  });

  final AsyncValue monitoringState;
  final bool globalVideo;
  final bool showDetails;
  final VoidCallback onToggleGlobalVideo;
  final VoidCallback onToggleShowDetails;
  final bool Function(String cameraId) isVideoOn;
  final void Function(String cameraId) onToggleCameraVideo;
  final Future<void> Function(String cameraId) onRemoveCamera;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return monitoringState.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (state) {
        final activityThreshold =
            ref.watch(settingsProvider).activityThreshold;
        if (state.cameras.isEmpty) {
          // Resuming or just-finished-stop transient — keep the chrome stable
          // while the new state lands.
          return const Center(child: CircularProgressIndicator());
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.all(Spacing.lg),
          child: Column(
            children: [
              _LiveToolbar(
                globalVideoOn: globalVideo,
                showDetails: showDetails,
                cameraCount: state.cameras.length,
                onToggleGlobalVideo: onToggleGlobalVideo,
                onToggleShowDetails: onToggleShowDetails,
              ),
              const SizedBox(height: Spacing.md),
              for (int i = 0; i < state.cameras.length; i++) ...[
                CameraAudioCard(
                  cameraState: state.cameras[i],
                  cameraIndex: i,
                  showVideoPreview: isVideoOn(state.cameras[i].cameraId),
                  showDebugInfo: showDetails,
                  activityThreshold: activityThreshold,
                  onToggleVideo: () =>
                      onToggleCameraVideo(state.cameras[i].cameraId),
                  onRemove: () => onRemoveCamera(state.cameras[i].cameraId),
                ),
                if (i < state.cameras.length - 1)
                  const SizedBox(height: Spacing.lg),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _LiveToolbar extends StatelessWidget {
  const _LiveToolbar({
    required this.globalVideoOn,
    required this.showDetails,
    required this.cameraCount,
    required this.onToggleGlobalVideo,
    required this.onToggleShowDetails,
  });

  final bool globalVideoOn;
  final bool showDetails;
  final int cameraCount;
  final VoidCallback onToggleGlobalVideo;
  final VoidCallback onToggleShowDetails;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        if (cameraCount > 2) ...[
          Chip(
            avatar: Icon(
              Icons.warning_amber_outlined,
              size: 16,
              color: theme.colorScheme.onTertiaryContainer,
            ),
            label: Text(
              'More than 2 cameras may degrade performance and battery life.',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onTertiaryContainer,
              ),
            ),
            backgroundColor: theme.colorScheme.tertiaryContainer,
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: Spacing.sm),
        ],
        Expanded(
          child: Text('Cameras', style: theme.textTheme.titleMedium),
        ),
        TextButton.icon(
          onPressed: onToggleShowDetails,
          icon: Icon(showDetails ? Icons.info : Icons.info_outline),
          label: Text(showDetails ? 'Hide details' : 'Show details'),
        ),
        TextButton.icon(
          onPressed: onToggleGlobalVideo,
          icon: Icon(globalVideoOn ? Icons.videocam : Icons.videocam_off),
          label: Text(globalVideoOn ? 'Hide video' : 'Show video'),
        ),
      ],
    );
  }
}

/// Idle state: pick cameras to monitor + Start Monitoring.
class _IdleCameraPicker extends ConsumerWidget {
  const _IdleCameraPicker({required this.onStart});

  final Future<void> Function() onStart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cameraState = ref.watch(cameraNotifierProvider);

    return cameraState.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Text('Error: $e',
            style: TextStyle(color: theme.colorScheme.error)),
      ),
      data: (state) {
        if (state.cameras.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.videocam_off_outlined,
                      size: 64,
                      color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(height: Spacing.lg),
                  Text('No cameras found',
                      style: theme.textTheme.titleLarge),
                  const SizedBox(height: Spacing.sm),
                  Text(
                    'Pull to refresh, or enable RTSP on a Protect camera.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: Spacing.lg),
                  TextButton.icon(
                    onPressed: () {
                      final host =
                          ref.read(authNotifierProvider).value?.host;
                      if (host != null) {
                        ref
                            .read(cameraNotifierProvider.notifier)
                            .loadCameras(host);
                      }
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Refresh'),
                  ),
                ],
              ),
            ),
          );
        }
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  Spacing.lg, Spacing.lg, Spacing.lg, Spacing.sm),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Choose cameras to monitor',
                      style: theme.textTheme.bodyLarge,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Refresh cameras',
                    onPressed: () {
                      final host =
                          ref.read(authNotifierProvider).value?.host;
                      if (host != null) {
                        ref
                            .read(cameraNotifierProvider.notifier)
                            .loadCameras(host);
                      }
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: state.cameras.length,
                itemBuilder: (_, i) {
                  final cam = state.cameras[i];
                  final selected = state.selectedIds.contains(cam.id);
                  return CheckboxListTile(
                    value: selected,
                    onChanged: (_) => ref
                        .read(cameraNotifierProvider.notifier)
                        .toggleCamera(cam.id),
                    title: Text(cam.name ?? 'Unnamed Camera'),
                    subtitle: Text(cam.state),
                    secondary: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: cam.isConnected
                            ? AppTheme.statusOnline
                            : AppTheme.statusOffline,
                      ),
                    ),
                  );
                },
              ),
            ),
            if (state.hasPerformanceRisk)
              Container(
                width: double.infinity,
                color: theme.colorScheme.tertiaryContainer,
                padding: const EdgeInsets.symmetric(
                    horizontal: Spacing.lg, vertical: Spacing.sm),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.warning_amber_outlined,
                      size: 18,
                      color: theme.colorScheme.onTertiaryContainer,
                    ),
                    const SizedBox(width: Spacing.sm),
                    Expanded(
                      child: Text(
                        'More than 2 cameras may degrade performance and battery life.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onTertiaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: Spacing.lg, vertical: Spacing.md),
                child: SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton.icon(
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Start monitoring'),
                    onPressed: state.canStartMonitoring ? () => onStart() : null,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
