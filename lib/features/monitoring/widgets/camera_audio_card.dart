import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/spacing.dart';
import '../../cameras/widgets/camera_source_badge.dart';
import '../models/player_state.dart';
import '../providers/audio_player_provider.dart';

/// Per-camera control card with volume slider, pan slider, status, mute,
/// quality selector, and optional video preview.
class CameraAudioCard extends ConsumerStatefulWidget {
  final CameraAudioState cameraState;
  final int cameraIndex;
  final bool showVideoPreview;
  final bool showDebugInfo;
  final double activityThreshold;
  final bool showSourceBadge;
  final VoidCallback? onToggleVideo;
  final VoidCallback? onRemove;

  const CameraAudioCard({
    super.key,
    required this.cameraState,
    required this.cameraIndex,
    this.showVideoPreview = false,
    this.showDebugInfo = false,
    this.activityThreshold = 0.05,
    this.showSourceBadge = false,
    this.onToggleVideo,
    this.onRemove,
  });

  @override
  ConsumerState<CameraAudioCard> createState() => _CameraAudioCardState();
}

class _CameraAudioCardState extends ConsumerState<CameraAudioCard> {
  final TransformationController _transformController =
      TransformationController();

  VideoController? get _videoController => ref
      .read(audioPlayerProvider.notifier)
      .getVideoController(widget.cameraState.cameraId);

  void _zoomIn() {
    final scale = _transformController.value.getMaxScaleOnAxis();
    if (scale < 5.0) {
      _transformController.value = _transformController.value.clone()
        ..multiply(Matrix4.diagonal3Values(1.5, 1.5, 1.0));
    }
  }

  void _zoomOut() {
    final scale = _transformController.value.getMaxScaleOnAxis();
    if (scale > 1.1) {
      final f = 1.0 / 1.5;
      _transformController.value = _transformController.value.clone()
        ..multiply(Matrix4.diagonal3Values(f, f, 1.0));
    } else {
      _transformController.value = Matrix4.identity();
    }
  }

  void _panBy(double dx, double dy) {
    final current = _transformController.value.clone();
    // Directly modify the translation entries in the 4x4 matrix.
    current[12] += dx; // x translation
    current[13] += dy; // y translation
    _transformController.value = current;
  }

  void _resetView() {
    _transformController.value = Matrix4.identity();
  }

  Future<void> _confirmRemove(BuildContext context) async {
    final onRemove = widget.onRemove;
    if (onRemove == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${widget.cameraState.cameraName}?'),
        content: const Text(
          'Stops just this camera. Other cameras keep monitoring. '
          'If this is the last camera, monitoring will stop.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      onRemove();
    }
  }

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = widget.cameraState;
    final idx = widget.cameraIndex;
    final isConnecting =
        cs.connectionStatus == CameraConnectionStatus.connecting;

    final videoCtrl = widget.showVideoPreview ? _videoController : null;

    // Google Meet-style border highlight on relative audio activity change.
    final hasActivity = cs.isLive && cs.audioActivity > widget.activityThreshold;
    final borderColor = hasActivity
        ? AppTheme.statusOnline.withValues(
            alpha: ((cs.audioActivity - widget.activityThreshold) /
                    (1.0 - widget.activityThreshold))
                .clamp(0.15, 0.9))
        : Colors.transparent;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: borderColor,
          width: 2.0,
        ),
      ),
      child: Card.filled(
        margin: EdgeInsets.zero,
        child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Row 1: Status dot + Camera name + Status text + Buttons
            // When reconnecting, the header row is wrapped in a tinted container
            // (UI-SPEC §Component Inventory #1). Tint stays on the inner row so
            // the outer AnimatedContainer border animation is unaffected.
            Container(
              padding: cs.connectionStatus == CameraConnectionStatus.reconnecting
                  ? const EdgeInsets.all(Spacing.sm)
                  : EdgeInsets.zero,
              decoration: cs.connectionStatus == CameraConnectionStatus.reconnecting
                  ? BoxDecoration(
                      color: theme.colorScheme.tertiaryContainer
                          .withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(8),
                    )
                  : null,
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: cs.isLive
                          ? AppTheme.statusOnline
                          : cs.isError
                              ? AppTheme.statusOffline
                              : cs.connectionStatus ==
                                      CameraConnectionStatus.reconnecting
                                  ? theme.colorScheme.tertiary
                                  : theme.colorScheme.onSurface
                                      .withValues(alpha: 0.5),
                    ),
                  ),
                  const SizedBox(width: Spacing.sm),
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            cs.cameraName,
                            style: theme.textTheme.titleMedium,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (widget.showSourceBadge) ...[
                          const SizedBox(width: Spacing.sm),
                          CameraSourceBadge(isManual: cs.isManual),
                        ],
                      ],
                    ),
                  ),
                  // Status text — exactly one branch renders per UI-SPEC
                  // Interaction States Matrix (idle renders nothing).
                  if (cs.isLive)
                    Text(
                      'Live',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: AppTheme.statusOnline),
                    )
                  else if (cs.isError)
                    Flexible(
                      child: Text(
                        cs.errorMessage ?? 'Stream failed',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: AppTheme.statusOffline),
                        overflow: TextOverflow.ellipsis,
                      ),
                    )
                  else if (cs.connectionStatus ==
                      CameraConnectionStatus.reconnecting)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.0,
                            valueColor: AlwaysStoppedAnimation(
                                theme.colorScheme.tertiary),
                          ),
                        ),
                        const SizedBox(width: Spacing.xs),
                        Text(
                          'Reconnecting…',
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: theme.colorScheme.tertiary),
                        ),
                      ],
                    )
                  else if (isConnecting)
                    Text('Connecting…', style: theme.textTheme.bodyMedium),
                  IconButton(
                    icon: Icon(
                      cs.isMuted ? Icons.volume_off : Icons.volume_up,
                    ),
                    tooltip: cs.isMuted ? 'Unmute' : 'Mute',
                    onPressed: () => ref
                        .read(audioPlayerProvider.notifier)
                        .toggleMute(idx),
                  ),
                  if (widget.onToggleVideo != null)
                    IconButton(
                      icon: Icon(
                        widget.showVideoPreview
                            ? Icons.videocam
                            : Icons.videocam_off,
                        size: 20,
                      ),
                      tooltip: widget.showVideoPreview
                          ? 'Hide video'
                          : 'Show video',
                      onPressed: widget.onToggleVideo,
                    ),
                  if (widget.onRemove != null)
                    IconButton(
                      icon: Icon(
                        Icons.close_rounded,
                        size: 20,
                        color: theme.colorScheme.error,
                      ),
                      tooltip: 'Remove from mix',
                      onPressed: () => _confirmRemove(context),
                    ),
                ],
              ),
            ),

            // Audio level indicator
            if (cs.isLive) ...[
              const SizedBox(height: Spacing.xs),
              _AudioLevelIndicator(
                level: cs.audioLevel,
                isSuspiciouslySilent: cs.isSuspiciouslySilent,
                silenceDuration: cs.silenceDuration,
              ),
            ],

            // Quality selector + stream URL debug info
            if (cs.availableQualities.isNotEmpty) ...[
              const SizedBox(height: Spacing.xs),
              Row(
                children: [
                  // Quality dropdown
                  DropdownButton<String>(
                    value: cs.activeQuality,
                    isDense: true,
                    underline: const SizedBox.shrink(),
                    style: theme.textTheme.bodySmall,
                    items: cs.availableQualities.keys.map((q) {
                      return DropdownMenuItem(
                        value: q,
                        child: Text(
                          q[0].toUpperCase() + q.substring(1),
                          style: theme.textTheme.bodySmall,
                        ),
                      );
                    }).toList(),
                    onChanged: cs.isLive
                        ? (q) {
                            if (q != null) {
                              ref
                                  .read(audioPlayerProvider.notifier)
                                  .switchQuality(idx, q);
                            }
                          }
                        : null,
                  ),
                ],
              ),
            ],

            // Debug/stream info
            if (widget.showDebugInfo && cs.isLive) ...[
              const SizedBox(height: Spacing.xs),
              _StreamInfoPanel(
                streamInfo: cs.streamInfo,
                cameraState: cs,
                showVideoInfo: widget.showVideoPreview,
              ),
            ],

            // Video preview with pinch-to-zoom and pan
            if (videoCtrl != null) ...[
              const SizedBox(height: Spacing.sm),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Stack(
                  children: [
                    AspectRatio(
                      aspectRatio: 16 / 9,
                      child: InteractiveViewer(
                        transformationController: _transformController,
                        minScale: 1.0,
                        maxScale: 5.0,
                        panEnabled: true,
                        scaleEnabled: true,
                        child: Video(
                          controller: videoCtrl,
                          controls: NoVideoControls,
                        ),
                      ),
                    ),
                    // Zoom + pan buttons overlay
                    Positioned(
                      right: Spacing.xs,
                      bottom: Spacing.xs,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Pan up
                          _OverlayButton(
                            icon: Icons.keyboard_arrow_up,
                            tooltip: 'Pan up',
                            onPressed: () => _panBy(0, 30),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _OverlayButton(
                                icon: Icons.keyboard_arrow_left,
                                tooltip: 'Pan left',
                                onPressed: () => _panBy(30, 0),
                              ),
                              const SizedBox(width: 2),
                              _OverlayButton(
                                icon: Icons.fit_screen,
                                tooltip: 'Reset view',
                                onPressed: _resetView,
                              ),
                              const SizedBox(width: 2),
                              _OverlayButton(
                                icon: Icons.keyboard_arrow_right,
                                tooltip: 'Pan right',
                                onPressed: () => _panBy(-30, 0),
                              ),
                            ],
                          ),
                          // Pan down + zoom
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _OverlayButton(
                                icon: Icons.zoom_out,
                                tooltip: 'Zoom out',
                                onPressed: _zoomOut,
                              ),
                              const SizedBox(width: 2),
                              _OverlayButton(
                                icon: Icons.keyboard_arrow_down,
                                tooltip: 'Pan down',
                                onPressed: () => _panBy(0, -30),
                              ),
                              const SizedBox(width: 2),
                              _OverlayButton(
                                icon: Icons.zoom_in,
                                tooltip: 'Zoom in',
                                onPressed: _zoomIn,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Show progress indicator when connecting instead of sliders
            if (isConnecting)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: Spacing.sm),
                child: LinearProgressIndicator(),
              ),

            // Row 2: Volume slider (only when not connecting)
            if (!isConnecting) ...[
              const SizedBox(height: Spacing.sm),
              Row(
                children: [
                  const Icon(Icons.volume_down, size: 20),
                  Expanded(
                    child: Slider(
                      value: cs.volume,
                      min: 0.0,
                      max: 100.0,
                      divisions: 100,
                      onChanged: cs.isLive
                          ? (v) => ref
                              .read(audioPlayerProvider.notifier)
                              .setVolume(idx, v)
                          : null,
                      semanticFormatterCallback: (v) =>
                          'Volume ${v.round()} percent',
                    ),
                  ),
                  SizedBox(
                    width: 40,
                    child: Text(
                      '${cs.volume.round()}%',
                      style: theme.textTheme.bodySmall,
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),

            ],
          ],
        ),
      ),
      ),  // close Card.filled
    );  // close AnimatedContainer
  }
}

class _AudioLevelIndicator extends StatelessWidget {
  final double level;
  final bool isSuspiciouslySilent;
  final double silenceDuration;

  const _AudioLevelIndicator({
    required this.level,
    required this.isSuspiciouslySilent,
    required this.silenceDuration,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Color: green when active, amber when low, red when suspiciously silent.
    final Color barColor;
    if (isSuspiciouslySilent) {
      barColor = AppTheme.statusOffline;
    } else if (level > 0.1) {
      barColor = AppTheme.statusOnline;
    } else {
      barColor = Colors.amber;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Level bar
        SizedBox(
          height: 4,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: isSuspiciouslySilent ? 0.0 : level.clamp(0.0, 1.0),
              backgroundColor: theme.colorScheme.onSurface.withValues(alpha: 0.1),
              valueColor: AlwaysStoppedAnimation(barColor),
            ),
          ),
        ),
        // Silence warning
        if (isSuspiciouslySilent) ...[
          const SizedBox(height: 2),
          Text(
            'No audio for ${silenceDuration.toStringAsFixed(0)}s — stream may be broken',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppTheme.statusOffline,
              fontSize: 11,
            ),
          ),
        ],
      ],
    );
  }
}

class _StreamInfoPanel extends StatelessWidget {
  final StreamInfo streamInfo;
  final CameraAudioState cameraState;
  final bool showVideoInfo;

  const _StreamInfoPanel({
    required this.streamInfo,
    required this.cameraState,
    required this.showVideoInfo,
  });

  String _formatBitrate(int? bps) {
    if (bps == null || bps <= 0) return '?';
    if (bps > 1000000) return '${(bps / 1000000).toStringAsFixed(1)} Mbps';
    return '${(bps / 1000).toStringAsFixed(0)} kbps';
  }

  String? _extractHost(String? url) {
    if (url == null) return null;
    final uri = Uri.tryParse(url);
    return uri?.host;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dimStyle = theme.textTheme.bodySmall?.copyWith(
      fontSize: 11,
      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
      fontFamily: 'monospace',
    );
    final labelStyle = dimStyle?.copyWith(
      color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
    );
    final si = streamInfo;

    final rows = <Widget>[];

    // Device info from Unifi API
    final nvrHost = _extractHost(cameraState.activeStreamUrl);
    if (nvrHost != null) {
      rows.add(_row('NVR', nvrHost, labelStyle, dimStyle));
    }
    final deviceParts = <String>[cameraState.cameraId];
    if (cameraState.modelKey != null) deviceParts.add(cameraState.modelKey!);
    if (cameraState.mac != null) deviceParts.add(cameraState.mac!);
    rows.add(_row('Device', deviceParts.join(' · '), labelStyle, dimStyle));
    if (cameraState.micVolume != null) {
      rows.add(_row('Mic Vol', '${cameraState.micVolume}%', labelStyle, dimStyle));
    }

    // Audio section
    final audioParts = <String>[];
    if (si.audioCodec != null) audioParts.add(si.audioCodec!);
    if (si.audioFormat != null) audioParts.add(si.audioFormat!);
    if (si.sampleRate != null) audioParts.add('${si.sampleRate} Hz');
    if (si.channels != null) audioParts.add(si.channels!);
    audioParts.add(_formatBitrate(si.audioBitrate));
    rows.add(_row('Audio', audioParts.join(' · '), labelStyle, dimStyle));

    // Video section (only when video preview is active)
    if (showVideoInfo) {
      final videoParts = <String>[];
      if (si.videoCodec != null) videoParts.add(si.videoCodec!);
      if (si.width != null && si.height != null) videoParts.add('${si.width}x${si.height}');
      if (si.fps != null && si.fps! > 0) videoParts.add('${si.fps!.toStringAsFixed(1)} fps');
      videoParts.add(_formatBitrate(si.videoBitrate));
      if (videoParts.isNotEmpty) {
        rows.add(_row('Video', videoParts.join(' · '), labelStyle, dimStyle));
      }
    }

    // Stream URL
    if (cameraState.activeStreamUrl != null) {
      rows.add(_row('URL', cameraState.activeStreamUrl!, labelStyle, dimStyle));
    }

    if (rows.isEmpty) {
      return Text('Waiting for stream info...', style: dimStyle);
    }

    return SelectionArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: rows,
      ),
    );
  }

  Widget _row(String label, String value, TextStyle? labelStyle, TextStyle? valueStyle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text('$label:', style: labelStyle),
          ),
          Expanded(
            child: Text(value, style: valueStyle, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}

class _OverlayButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _OverlayButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black54,
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Tooltip(
            message: tooltip,
            child: Icon(icon, size: 18, color: Colors.white),
          ),
        ),
      ),
    );
  }
}
