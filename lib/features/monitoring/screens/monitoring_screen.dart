import 'dart:io' show Platform;
import 'dart:math' as math;

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
import '../../cameras/models/protect_camera.dart';
import '../../cameras/providers/camera_provider.dart';
import '../../cameras/widgets/camera_source_badge.dart';
import '../models/player_state.dart';
import '../providers/audio_player_provider.dart';
import '../providers/session_history_provider.dart';
import '../services/audio_handler.dart';
import '../widgets/camera_audio_card.dart';

/// Width at which we switch the idle picker from list to grid layout.
const double _kWideLayoutBreakpoint = 600;

/// Lays out [count] items in as many columns as fit at `targetMax` per item,
/// without letting any item shrink below `floor`. Returns the resulting
/// column count and the per-item width.
({int cols, double itemWidth}) _fluidGrid({
  required double available,
  required double targetMax,
  required double floor,
  required double spacing,
}) {
  if (available <= 0) return (cols: 1, itemWidth: math.max(0, available));
  int cols =
      math.max(1, ((available + spacing) / (targetMax + spacing)).ceil());
  double itemWidth = (available - (cols - 1) * spacing) / cols;
  // Don't let items collapse below the minimum usable width.
  while (cols > 1 && itemWidth < floor) {
    cols--;
    itemWidth = (available - (cols - 1) * spacing) / cols;
  }
  return (cols: cols, itemWidth: itemWidth);
}

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

  final AsyncValue<MonitoringState> monitoringState;
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
        // Only distinguish sources when both types are actually being monitored.
        final showSourceBadge = state.cameras.any((c) => c.isManual) &&
            state.cameras.any((c) => !c.isManual);
        return LayoutBuilder(
          builder: (context, constraints) {
            // Fluid card grid: target ~480dp per card, never below ~340dp.
            // Variable-height cards rule out GridView (which forces an
            // aspect ratio), so we use a Wrap with a computed item width.
            // Items in the same row align to top edges, which is fine when
            // an open video preview makes one card taller than its row-mates.
            final available = constraints.maxWidth - Spacing.lg * 2;
            final grid = _fluidGrid(
              available: available,
              targetMax: 480,
              floor: 340,
              spacing: Spacing.lg,
            );
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
                  Wrap(
                    spacing: Spacing.lg,
                    runSpacing: Spacing.lg,
                    children: [
                      for (int i = 0; i < state.cameras.length; i++)
                        SizedBox(
                          width: grid.itemWidth,
                          child: CameraAudioCard(
                            cameraState: state.cameras[i],
                            cameraIndex: i,
                            showVideoPreview:
                                isVideoOn(state.cameras[i].cameraId),
                            showDebugInfo: showDetails,
                            activityThreshold: activityThreshold,
                            showSourceBadge: showSourceBadge,
                            onToggleVideo: () => onToggleCameraVideo(
                                state.cameras[i].cameraId),
                            onRemove: () =>
                                onRemoveCamera(state.cameras[i].cameraId),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            );
          },
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
    return LayoutBuilder(
      builder: (context, constraints) {
        // Below this width the two labelled toggle buttons + the title no
        // longer fit on one line, so collapse the toggles to icon-only.
        final compact = constraints.maxWidth < 460;
        final detailsIcon = showDetails ? Icons.info : Icons.info_outline;
        final detailsLabel = showDetails ? 'Hide details' : 'Show details';
        final videoIcon =
            globalVideoOn ? Icons.videocam : Icons.videocam_off;
        final videoLabel = globalVideoOn ? 'Hide video' : 'Show video';
        return Row(
          children: [
            if (cameraCount > 2) ...[
              Flexible(
                child: Chip(
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
              ),
              const SizedBox(width: Spacing.sm),
            ],
            Expanded(
              child: Text(
                'Cameras',
                style: theme.textTheme.titleMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (compact) ...[
              IconButton(
                onPressed: onToggleShowDetails,
                icon: Icon(detailsIcon),
                tooltip: detailsLabel,
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                onPressed: onToggleGlobalVideo,
                icon: Icon(videoIcon),
                tooltip: videoLabel,
                visualDensity: VisualDensity.compact,
              ),
            ] else ...[
              TextButton.icon(
                onPressed: onToggleShowDetails,
                icon: Icon(detailsIcon),
                label: Text(detailsLabel),
              ),
              TextButton.icon(
                onPressed: onToggleGlobalVideo,
                icon: Icon(videoIcon),
                label: Text(videoLabel),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// Validate a manually-entered RTSP/RTSPS URL. Returns an error string for an
/// invalid form field, or null when acceptable.
String? _validateRtspUrl(String? v) {
  final value = v?.trim() ?? '';
  if (value.isEmpty) return 'Required';
  final uri = Uri.tryParse(value);
  if (uri == null ||
      (uri.scheme != 'rtsp' && uri.scheme != 'rtsps') ||
      uri.host.isEmpty) {
    return 'Enter a valid rtsp:// or rtsps:// URL';
  }
  return null;
}

/// Validate an OPTIONAL RTSP/RTSPS URL field: empty is fine, but a non-empty
/// value must be a valid rtsp:// or rtsps:// URL.
String? _validateOptionalRtspUrl(String? v) {
  final value = v?.trim() ?? '';
  if (value.isEmpty) return null;
  return _validateRtspUrl(value);
}

/// Prompt for a manual RTSP camera (name + URL + optional remote URL) and add
/// it on confirm.
Future<void> _showAddManualCameraDialog(
    BuildContext context, WidgetRef ref) async {
  final nameController = TextEditingController();
  final urlController = TextEditingController();
  final remoteUrlController = TextEditingController();
  final formKey = GlobalKey<FormState>();
  try {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add RTSP camera'),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Name (optional)',
                    hintText: 'Nursery',
                    border: OutlineInputBorder(),
                  ),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: Spacing.md),
                TextFormField(
                  controller: urlController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'RTSP URL',
                    hintText: 'rtsp://192.168.1.50:554/stream',
                    border: OutlineInputBorder(),
                  ),
                  autocorrect: false,
                  validator: _validateRtspUrl,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: Spacing.md),
                TextFormField(
                  controller: remoteUrlController,
                  decoration: const InputDecoration(
                    labelText: 'Remote URL (optional)',
                    hintText: 'rtsp://100.64.0.9:554/stream',
                    helperText: 'VPN/Tailscale fallback tried when the '
                        'primary URL is unreachable.',
                    helperMaxLines: 2,
                    border: OutlineInputBorder(),
                  ),
                  autocorrect: false,
                  validator: _validateOptionalRtspUrl,
                  onFieldSubmitted: (_) {
                    if (formKey.currentState!.validate()) {
                      Navigator.of(ctx).pop(true);
                    }
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.of(ctx).pop(true);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(cameraNotifierProvider.notifier).addManualCamera(
            url: urlController.text,
            name: nameController.text,
            remoteUrl: remoteUrlController.text,
          );
    }
  } finally {
    nameController.dispose();
    urlController.dispose();
    remoteUrlController.dispose();
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
    // Manual-only setups have no Unifi console to refresh against.
    final isManualMode =
        ref.watch(authNotifierProvider).value?.isManualMode ?? false;
    final canRefresh = !isManualMode;

    void refresh() {
      final host = ref.read(authNotifierProvider).value?.host;
      if (host != null) {
        ref.read(cameraNotifierProvider.notifier).loadCameras(host);
      }
    }

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
                  Text('No cameras yet',
                      style: theme.textTheme.titleLarge),
                  const SizedBox(height: Spacing.sm),
                  Text(
                    isManualMode
                        ? 'Add a camera by entering its RTSP stream URL.'
                        : 'Add an RTSP URL manually, or enable RTSP on a '
                            'Protect camera and refresh.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: Spacing.lg),
                  FilledButton.icon(
                    onPressed: () =>
                        _showAddManualCameraDialog(context, ref),
                    icon: const Icon(Icons.add),
                    label: const Text('Add RTSP camera'),
                  ),
                  if (canRefresh) ...[
                    const SizedBox(height: Spacing.sm),
                    TextButton.icon(
                      onPressed: refresh,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Refresh'),
                    ),
                  ],
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
                    icon: const Icon(Icons.add),
                    tooltip: 'Add RTSP camera',
                    onPressed: () =>
                        _showAddManualCameraDialog(context, ref),
                  ),
                  if (canRefresh)
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      tooltip: 'Refresh cameras',
                      onPressed: refresh,
                    ),
                ],
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isWide =
                      constraints.maxWidth >= _kWideLayoutBreakpoint;
                  if (!isWide) {
                    return ListView.builder(
                      itemCount: state.cameras.length,
                      itemBuilder: (_, i) {
                        final cam = state.cameras[i];
                        final selected = state.selectedIds.contains(cam.id);
                        final url = cam.defaultStreamUrl;
                        return CheckboxListTile(
                          value: selected,
                          onChanged: (_) => ref
                              .read(cameraNotifierProvider.notifier)
                              .toggleCamera(cam.id),
                          title: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  cam.name ?? 'Unnamed Camera',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (state.hasMixedSources) ...[
                                const SizedBox(width: Spacing.sm),
                                CameraSourceBadge(isManual: cam.isManual),
                              ],
                            ],
                          ),
                          subtitle: Text(
                            cam.isManual ? (url ?? 'RTSP stream') : cam.state,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          secondary: cam.isManual
                              ? IconButton(
                                  icon: Icon(
                                    Icons.delete_outline,
                                    color: theme.colorScheme.error,
                                  ),
                                  tooltip: 'Remove camera',
                                  onPressed: () => ref
                                      .read(cameraNotifierProvider.notifier)
                                      .removeManualCamera(cam.id),
                                )
                              : Container(
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
                    );
                  }
                  final available = constraints.maxWidth - Spacing.lg * 2;
                  final grid = _fluidGrid(
                    available: available,
                    targetMax: 280,
                    floor: 220,
                    spacing: Spacing.md,
                  );
                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(
                        Spacing.lg, 0, Spacing.lg, Spacing.lg),
                    child: Wrap(
                      spacing: Spacing.md,
                      runSpacing: Spacing.md,
                      children: [
                        for (final cam in state.cameras)
                          SizedBox(
                            width: grid.itemWidth,
                            child: _CameraPickerTile(
                              camera: cam,
                              selected: state.selectedIds.contains(cam.id),
                              showSource: state.hasMixedSources,
                              onToggle: () => ref
                                  .read(cameraNotifierProvider.notifier)
                                  .toggleCamera(cam.id),
                              onDelete: cam.isManual
                                  ? () => ref
                                      .read(cameraNotifierProvider.notifier)
                                      .removeManualCamera(cam.id)
                                  : null,
                            ),
                          ),
                      ],
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

/// Wide-layout checkable camera tile used by the idle picker grid.
class _CameraPickerTile extends StatelessWidget {
  const _CameraPickerTile({
    required this.camera,
    required this.selected,
    required this.onToggle,
    this.showSource = false,
    this.onDelete,
  });

  final ProtectCamera camera;
  final bool selected;
  final bool showSource;
  final VoidCallback onToggle;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderColor = selected
        ? theme.colorScheme.primary
        : theme.colorScheme.outlineVariant;
    final subtitle =
        camera.isManual ? (camera.defaultStreamUrl ?? 'RTSP stream') : camera.state;
    return Material(
      color: selected
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.4)
          : theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onToggle,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: borderColor,
              width: selected ? 2 : 1,
            ),
          ),
          padding: const EdgeInsets.all(Spacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Checkbox(
                value: selected,
                onChanged: (_) => onToggle(),
              ),
              const SizedBox(width: Spacing.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            camera.name ?? 'Unnamed Camera',
                            style: theme.textTheme.titleSmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (showSource) ...[
                          const SizedBox(width: Spacing.xs),
                          CameraSourceBadge(isManual: camera.isManual),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        if (!camera.isManual) ...[
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: camera.isConnected
                                  ? AppTheme.statusOnline
                                  : AppTheme.statusOffline,
                            ),
                          ),
                          const SizedBox(width: Spacing.xs),
                        ],
                        Flexible(
                          child: Text(
                            subtitle,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (onDelete != null)
                IconButton(
                  icon: Icon(
                    Icons.delete_outline,
                    size: 20,
                    color: theme.colorScheme.error,
                  ),
                  tooltip: 'Remove camera',
                  onPressed: onDelete,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
