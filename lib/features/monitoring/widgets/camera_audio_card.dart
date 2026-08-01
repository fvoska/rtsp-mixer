import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../../core/logging/app_logger.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/spacing.dart';
import '../../../core/theme/status_colors.dart';
import '../../cameras/widgets/camera_source_badge.dart';
import '../helpers/audio_level_meter.dart';
import '../models/player_state.dart';
import '../providers/audio_player_provider.dart';

/// Normalised, sanitised activity intensity in `[0.15, 0.9]`, or null when the
/// input cannot be trusted.
///
/// `audioActivity` is written by a twice-a-second poll of mpv properties. A
/// NaN, an infinity, or a threshold of exactly 1.0 would produce an invalid
/// `BoxShadow` and throw out of `build` — during an overnight session, with
/// audio playing. Per CLAUDE.md a silently haloless card is the correct
/// degraded mode; an exception is not.
double? _activityIntensity(double activity, double threshold) {
  try {
    if (!activity.isFinite || !threshold.isFinite) return null;
    if (threshold >= 1.0) return null;
    final normalised = (activity - threshold) / (1.0 - threshold);
    if (!normalised.isFinite) return null;
    return normalised.clamp(0.15, 0.9);
  } catch (e) {
    _warnHaloOnce(e);
    return null;
  }
}

bool _haloWarned = false;

void _warnHaloOnce(Object error) {
  if (_haloWarned) return;
  _haloWarned = true;
  try {
    appLog('CARD', 'Activity halo disabled after bad input: $error');
  } catch (_) {}
}

/// Per-camera control card with volume slider, status, mute, quality
/// selector, and optional video preview.
///
/// (The doc comment used to promise a pan slider too. There has never been one
/// in this widget — L/R panning is deferred because the prebuilt media_kit
/// FFmpeg ships no `pan` filter, see CLAUDE.md.)
class CameraAudioCard extends ConsumerStatefulWidget {
  final CameraAudioState cameraState;
  final int cameraIndex;
  final bool showVideoPreview;
  final bool showDebugInfo;
  final double activityThreshold;
  final bool batterySaverMode;
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
    this.batterySaverMode = false,
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
    final status = context.statusColors;
    final cs = widget.cameraState;
    final idx = widget.cameraIndex;
    final isConnecting =
        cs.connectionStatus == CameraConnectionStatus.connecting;

    final videoCtrl = widget.showVideoPreview ? _videoController : null;

    // Google Meet-style highlight on recent VARIATION in pseudo-SPL
    // (peak-to-trough of the level history over ~5 s). A baby crying means
    // big swings, so the card lights up on change bursts — not on steady
    // loudness and not on deviation-from-baseline.
    final hasActivity = cs.isLive && cs.audioActivity > widget.activityThreshold;
    final intensity = hasActivity
        ? _activityIntensity(cs.audioActivity, widget.activityThreshold)
        : null;
    final borderColor =
        intensity != null ? status.live.withValues(alpha: intensity) : null;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.card),
        border: Border.all(
          color: borderColor ?? Colors.transparent,
          width: 2.0,
        ),
        // Nightwatch halo: the same tuned intensity that drives the border
        // also drives a soft outward glow, so a noisy room reads from across
        // the room instead of needing a squint at a 2px outline. Null (no
        // shadow) whenever the intensity could not be trusted.
        boxShadow: intensity == null
            ? null
            : [
                BoxShadow(
                  color: status.live.withValues(alpha: intensity * 0.55),
                  blurRadius: 8.0 + intensity * 20.0,
                  spreadRadius: intensity * 6.0,
                ),
              ],
      ),
      child: Card.filled(
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.card),
        ),
        // Clip so the edge-to-edge status banner honours the card's rounded
        // top corners.
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Zone 0: edge-to-edge status BANNER for problem states only
            // (reconnecting / error). Healthy states carry no banner and start
            // with the header. Both problem states share the SAME slot/widget
            // so cards stay structurally consistent — differing only in colour
            // and copy. This replaces the old per-state header tint box.
            // The banner is always present in the tree so it can grow/fade in
            // and collapse/fade out instead of popping. AnimatedSize animates
            // the height; AnimatedSwitcher fades the content. Clip + topCenter
            // keep a mid-collapse height from painting outside the card.
            AnimatedSize(
              duration: const Duration(milliseconds: 250),
              alignment: Alignment.topCenter,
              clipBehavior: Clip.hardEdge,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: (cs.connectionStatus ==
                            CameraConnectionStatus.reconnecting ||
                        cs.isError)
                    ? _StatusBanner(
                        status: cs.connectionStatus,
                        errorMessage: cs.errorMessage,
                      )
                    : const SizedBox.shrink(key: ValueKey('no-banner')),
              ),
            ),
            Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Zone 1: HEADER — identity (status dot + name + optional badge)
            // and the three action buttons only. No status text lives here and
            // the row is never tinted, so every state's header is identical.
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: cs.isLive
                        ? status.live
                        : cs.isError
                            ? status.offline
                            : cs.connectionStatus ==
                                    CameraConnectionStatus.reconnecting
                                ? status.reconnecting
                                : theme.colorScheme.onSurface
                                    .withValues(alpha: 0.5),
                  ),
                ),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  // With the status text gone from this row, a plain Expanded
                  // gives the name maximal room.
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          cs.cameraName,
                          style: theme.textTheme.titleMedium,
                          maxLines: 1,
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
                // Action buttons. Each is a full 48dp target — this row is
                // tapped one-handed in the dark.
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: Touch.target,
                        minHeight: Touch.target,
                      ),
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
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: Touch.target,
                          minHeight: Touch.target,
                        ),
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
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: Touch.target,
                          minHeight: Touch.target,
                        ),
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
              ],
            ),

            // Zone 2: STATUS LINE — healthy states only (Live / Connecting…)
            // get a dedicated full-width line below the header. Reconnecting /
            // error are carried by the banner; idle renders nothing. The
            // AnimatedSize animates the height as the line appears/disappears;
            // the crossfade between Live ↔ Connecting… lives inside _StatusLine.
            AnimatedSize(
              duration: const Duration(milliseconds: 250),
              alignment: Alignment.topCenter,
              clipBehavior: Clip.hardEdge,
              child: _StatusLine(status: cs.connectionStatus),
            ),

            // Audio level indicator + rolling waveform — replaced by a
            // lightweight notice in battery saver mode, since the poll no
            // longer updates level/history/activity and a frozen meter would
            // read as broken rather than intentionally paused.
            if (cs.isLive) ...[
              const SizedBox(height: Spacing.sm),
              if (widget.batterySaverMode)
                _BatterySaverNotice(
                  isSuspiciouslySilent: cs.isSuspiciouslySilent,
                  silenceDuration: cs.silenceDuration,
                )
              else ...[
                _AudioLevelIndicator(
                  level: cs.audioLevel,
                  isSuspiciouslySilent: cs.isSuspiciouslySilent,
                  silenceDuration: cs.silenceDuration,
                ),
                const SizedBox(height: Spacing.sm),
                _WaveformChart(history: cs.levelHistory),
              ],
            ],

            // Quality selector + stream URL debug info
            if (cs.availableQualities.isNotEmpty) ...[
              const SizedBox(height: Spacing.sm),
              Row(
                children: [
                  // Quality dropdown
                  DropdownButton<String>(
                    value: cs.activeQuality,
                    // Not dense: this is a real control and needs a real
                    // target, not a 24dp strip of text.
                    isDense: false,
                    itemHeight: Touch.target,
                    underline: const SizedBox.shrink(),
                    style: theme.textTheme.bodySmall,
                    items: cs.availableQualities.keys.map((q) {
                      return DropdownMenuItem(
                        value: q,
                        child: Text(
                          q.isEmpty
                              ? q
                              : q[0].toUpperCase() + q.substring(1),
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
              const SizedBox(height: Spacing.sm),
              _StreamInfoPanel(
                streamInfo: cs.streamInfo,
                cameraState: cs,
                showVideoInfo: widget.showVideoPreview,
              ),
            ],

            // Video preview with pinch-to-zoom and pan
            if (videoCtrl != null) ...[
              const SizedBox(height: Spacing.md),
              ClipRRect(
                // Nested inside a 20px card, so this rounds less.
                borderRadius: BorderRadius.circular(Radii.inner),
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

            // Connecting shows a LinearProgressIndicator; every other state
            // shows the volume slider row. Wrapping the either/or region in an
            // AnimatedSize (height) + fade-only AnimatedSwitcher (content)
            // crossfades the indicator into the slider row with no height jump.
            AnimatedSize(
              duration: const Duration(milliseconds: 250),
              alignment: Alignment.topCenter,
              clipBehavior: Clip.hardEdge,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: isConnecting
                    ? const Padding(
                        key: ValueKey('connecting-indicator'),
                        padding: EdgeInsets.symmetric(vertical: Spacing.sm),
                        child: LinearProgressIndicator(),
                      )
                    : Column(
                        key: const ValueKey('volume-row'),
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(height: Spacing.md),
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
                                width: 48,
                                // Muted clarity: show the word "Muted" in the
                                // volume row so the state reads without relying
                                // on the header icon. The AnimatedSwitcher
                                // crossfades Muted ↔ percentage.
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 200),
                                  child: Text(
                                    cs.isMuted
                                        ? 'Muted'
                                        : '${cs.volume.round()}%',
                                    key: ValueKey(cs.isMuted
                                        ? 'Muted'
                                        : '${cs.volume.round()}%'),
                                    style: cs.isMuted
                                        ? theme.textTheme.bodySmall
                                            ?.copyWith(color: status.offline)
                                        : theme.textTheme.bodySmall,
                                    textAlign: TextAlign.right,
                                    maxLines: 1,
                                    softWrap: false,
                                    overflow: TextOverflow.clip,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
              ),
            ),
          ],  // close inner Column children
        ),  // close inner Column
            ),  // close Padding
          ],  // close outer Column children
        ),  // close outer Column
      ),  // close Card.filled
    );  // close AnimatedContainer
  }
}

/// Edge-to-edge tinted status strip at the very top of the card, used only for
/// the problem states (reconnecting / error). Both states share this one widget
/// in the same slot — differing only in colour and copy — so problem cards stay
/// structurally consistent while being scannable by colour from a distance.
class _StatusBanner extends StatelessWidget {
  final CameraConnectionStatus status;
  final String? errorMessage;

  const _StatusBanner({required this.status, this.errorMessage});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final statusColors = context.statusColors;
    final bool isReconnecting =
        status == CameraConnectionStatus.reconnecting;

    // D-10: the amber accent is reserved for reconnecting only.
    final Color background = isReconnecting
        ? scheme.tertiaryContainer.withValues(alpha: 0.3)
        : statusColors.offline.withValues(alpha: 0.12);
    final Color foreground =
        isReconnecting ? statusColors.reconnecting : statusColors.offline;

    final Widget leading = isReconnecting
        ? SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2.0,
              valueColor: AlwaysStoppedAnimation(statusColors.reconnecting),
            ),
          )
        : Icon(
            Icons.error_outline,
            size: 14,
            color: statusColors.offline,
          );

    // D-11: reconnecting is status-ONLY — no attempt count, countdown, or
    // error text. Error wraps up to 3 lines across the full card width.
    final String label =
        isReconnecting ? 'Reconnecting…' : (errorMessage ?? 'Stream failed');
    final int maxLines = isReconnecting ? 1 : 3;

    // Optically center the 14x14 leading box on the FIRST text line. Deriving
    // the single-line height from the label's TextStyle keeps the icon aligned
    // to line one for the multi-line error case (rather than the block center),
    // while still centering the single-line reconnecting label.
    final TextStyle? labelStyle = theme.textTheme.bodyMedium;
    final double? labelFontSize = labelStyle?.fontSize;
    final double firstLineHeight = labelFontSize != null
        ? labelFontSize * (labelStyle?.height ?? 1.0)
        : 20.0;

    return Container(
      key: const ValueKey('status-banner'),
      width: double.infinity,
      color: background,
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.md,
        vertical: Spacing.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: firstLineHeight,
            child: Center(
              child:
                  SizedBox(width: 14, height: 14, child: Center(child: leading)),
            ),
          ),
          const SizedBox(width: Spacing.xs),
          Expanded(
            child: Text(
              label,
              maxLines: maxLines,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(color: foreground),
            ),
          ),
        ],
      ),
    );
  }
}

/// Full-width status line below the header for the healthy states
/// (playing → "Live", connecting → "Connecting…"). All other states render
/// nothing (problem states use the banner; idle shows no status). Because the
/// label sits in an Expanded on its own line it gets the full card width and
/// never truncates.
class _StatusLine extends StatelessWidget {
  final CameraConnectionStatus status;

  const _StatusLine({required this.status});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final statusColors = context.statusColors;

    Widget content;

    switch (status) {
      case CameraConnectionStatus.playing:
      case CameraConnectionStatus.connecting:
        final bool isConnecting =
            status == CameraConnectionStatus.connecting;
        final Widget leading = isConnecting
            ? SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2.0,
                  valueColor: AlwaysStoppedAnimation(scheme.primary),
                ),
              )
            : Icon(
                Icons.graphic_eq,
                size: 14,
                color: statusColors.live,
              );
        final String label = isConnecting ? 'Connecting…' : 'Live';
        final Color color =
            isConnecting ? scheme.primary : statusColors.live;
        content = Column(
          // Keyed by status so Live ↔ Connecting… crossfades in the switcher.
          key: ValueKey(status),
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: Spacing.sm),
            Row(
              // The label is always single-line here, so centering the 14x14
              // leading box against the taller text line-box optically centers
              // the spinner/icon with its label.
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(width: 14, height: 14, child: Center(child: leading)),
                const SizedBox(width: Spacing.xs),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(color: color),
                  ),
                ),
              ],
            ),
          ],
        );
        break;
      case CameraConnectionStatus.idle:
      case CameraConnectionStatus.reconnecting:
      case CameraConnectionStatus.error:
        content = SizedBox.shrink(key: ValueKey(status));
        break;
    }

    // Fade-only switcher: opacity animates but the child's layout size is
    // unchanged mid-animation, so the layout sweep's paragraph-size checks and
    // the bounded pump() finders stay valid.
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: content,
    );
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

    // Color: red only when suspiciously silent, otherwise green. The bar
    // shows an ABSOLUTE pseudo-SPL now, so a low level is a normally quiet
    // nursery — not a degraded state. An amber "low" branch would glow all
    // night; deliberately removed (pinned by a widget test).
    final statusColors = context.statusColors;
    final Color barColor =
        isSuspiciouslySilent ? statusColors.offline : statusColors.live;

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
              color: statusColors.offline,
              fontSize: 11,
            ),
          ),
        ],
      ],
    );
  }
}

/// Battery saver stand-in for [_AudioLevelIndicator] + the waveform. The
/// level/activity poll is skipped in this mode, so no meter is drawn — but
/// the silence warning is still real (silence detection stays on regardless
/// of battery saver) and worth surfacing here rather than dropping silently.
class _BatterySaverNotice extends StatelessWidget {
  final bool isSuspiciouslySilent;
  final double silenceDuration;

  const _BatterySaverNotice({
    required this.isSuspiciouslySilent,
    required this.silenceDuration,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColors = context.statusColors;

    if (isSuspiciouslySilent) {
      return Text(
        'No audio for ${silenceDuration.toStringAsFixed(0)}s — stream may be broken',
        style: theme.textTheme.bodySmall?.copyWith(
          color: statusColors.offline,
          fontSize: 11,
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.battery_saver_outlined,
          size: 14,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: Spacing.xs),
        Text(
          'Battery saver — level meter off, streaming as normal',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

/// Audacity-style mirrored waveform of the rolling pseudo-SPL history
/// (10 s / [kLevelHistoryCapacity] samples). Newest sample is always the
/// rightmost bar, oldest left, matching a scrolling recorder. Wrapped in a
/// [RepaintBoundary] so its twice-a-second repaints don't invalidate the
/// rest of the card.
class _WaveformChart extends StatelessWidget {
  final List<double> history;

  const _WaveformChart({required this.history});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return RepaintBoundary(
      child: CustomPaint(
        key: const ValueKey('waveform-chart'),
        size: const Size(double.infinity, 40),
        painter: _WaveformPainter(
          history: history,
          centerLineColor: scheme.onSurface.withValues(alpha: 0.15),
          barColor: scheme.primary.withValues(alpha: 0.8),
        ),
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final List<double> history;
  final Color centerLineColor;
  final Color barColor;

  const _WaveformPainter({
    required this.history,
    required this.centerLineColor,
    required this.barColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;

    // 1 px horizontal center line across the full width.
    canvas.drawRect(
      Rect.fromLTWH(0, centerY - 0.5, size.width, 1),
      Paint()..color = centerLineColor,
    );

    if (history.isEmpty || size.width <= 0) return;

    // Defensive: never draw more samples than the fixed slot grid holds.
    final samples = history.length > kLevelHistoryCapacity
        ? history.sublist(history.length - kLevelHistoryCapacity)
        : history;

    // Fixed slot grid so a partially-filled history grows from the RIGHT
    // edge: the newest sample is always rightmost (scrolling recorder).
    final slotWidth = size.width / kLevelHistoryCapacity;
    final firstSlot = kLevelHistoryCapacity - samples.length;
    final maxHalfHeight = centerY - 1;
    final barPaint = Paint()..color = barColor;
    final barWidth = math.max(slotWidth - 2.0, 1.0); // ~2 px gap between bars

    for (var i = 0; i < samples.length; i++) {
      final sample = samples[i].clamp(0.0, 1.0);
      // Mirrored bar around the center line; minimum 1 px half-height so
      // silence still shows a tick.
      final halfHeight = math.max(1.0, sample * maxHalfHeight);
      final left = (firstSlot + i) * slotWidth + 1.0;
      canvas.drawRect(
        Rect.fromLTWH(left, centerY - halfHeight, barWidth, halfHeight * 2),
        barPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter oldDelegate) =>
      // Each poll tick produces a NEW history list instance, so identity
      // comparison is correct and cheap (no per-sample equality walk).
      !identical(history, oldDelegate.history) ||
      centerLineColor != oldDelegate.centerLineColor ||
      barColor != oldDelegate.barColor;
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
    // Vendored Roboto Mono with tabular figures: these rows tick every poll,
    // and a proportional (or platform-default 'monospace') face made the
    // values shuffle sideways as digits changed.
    final dimStyle = AppTypography.numericSmall.copyWith(
      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
    );
    final labelStyle = dimStyle.copyWith(
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
    // Full 48dp target: these sit over a live video preview and were a 26dp
    // square, which is not hittable one-handed in the dark.
    return SizedBox(
      width: Touch.target,
      height: Touch.target,
      child: Material(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(Radii.control),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.control),
          onTap: onPressed,
          child: Tooltip(
            message: tooltip,
            child: Icon(icon, size: 20, color: Colors.white),
          ),
        ),
      ),
    );
  }
}
