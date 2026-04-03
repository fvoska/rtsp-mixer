import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/spacing.dart';
import '../models/player_state.dart';
import '../providers/audio_player_provider.dart';

/// Per-camera control card with volume slider, pan slider, status, and mute.
class CameraAudioCard extends ConsumerWidget {
  final CameraAudioState cameraState;
  final int cameraIndex;

  const CameraAudioCard({
    super.key,
    required this.cameraState,
    required this.cameraIndex,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isConnecting =
        cameraState.connectionStatus == CameraConnectionStatus.connecting;

    return Card.filled(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Row 1: Status dot + Camera name + Status text + Mute button
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: cameraState.isLive
                        ? AppTheme.statusOnline
                        : cameraState.isError
                            ? AppTheme.statusOffline
                            : theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: Text(
                    cameraState.cameraName,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                if (isConnecting)
                  Text('Connecting...', style: theme.textTheme.bodyMedium),
                if (cameraState.isLive)
                  Text(
                    'Live',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: AppTheme.statusOnline),
                  ),
                if (cameraState.isError)
                  Flexible(
                    child: Text(
                      cameraState.errorMessage ?? 'Stream failed',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: AppTheme.statusOffline),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                IconButton(
                  icon: Icon(
                    cameraState.isMuted ? Icons.volume_off : Icons.volume_up,
                  ),
                  tooltip: cameraState.isMuted ? 'Unmute' : 'Mute',
                  onPressed: () => ref
                      .read(audioPlayerProvider.notifier)
                      .toggleMute(cameraIndex),
                ),
              ],
            ),

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
                      value: cameraState.volume,
                      min: 0.0,
                      max: 100.0,
                      divisions: 100,
                      onChanged: cameraState.isLive
                          ? (v) => ref
                              .read(audioPlayerProvider.notifier)
                              .setVolume(cameraIndex, v)
                          : null,
                      semanticFormatterCallback: (v) =>
                          'Volume ${v.round()} percent',
                    ),
                  ),
                  SizedBox(
                    width: 40,
                    child: Text(
                      '${cameraState.volume.round()}%',
                      style: theme.textTheme.bodySmall,
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),

              // Row 3: Pan slider
              Row(
                children: [
                  Text('L', style: theme.textTheme.bodySmall),
                  Expanded(
                    child: Slider(
                      value: cameraState.pan,
                      min: -1.0,
                      max: 1.0,
                      divisions: 20,
                      onChanged: cameraState.isLive
                          ? (v) => ref
                              .read(audioPlayerProvider.notifier)
                              .setPan(cameraIndex, v)
                          : null,
                      semanticFormatterCallback: (v) {
                        if (v.abs() < 0.05) return 'Pan center';
                        final pct = (v.abs() * 100).round();
                        return v < 0
                            ? 'Pan $pct percent left'
                            : 'Pan $pct percent right';
                      },
                    ),
                  ),
                  Text('R', style: theme.textTheme.bodySmall),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
