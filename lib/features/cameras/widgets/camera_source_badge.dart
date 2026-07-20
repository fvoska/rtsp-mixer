import 'package:flutter/material.dart';

/// Small chip labelling a camera's source (UniFi vs manual RTSP). Callers only
/// show it when both source types are present — a single-source list needs no
/// distinction.
class CameraSourceBadge extends StatelessWidget {
  const CameraSourceBadge({super.key, required this.isManual});

  final bool isManual;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = isManual ? 'Manual' : 'UniFi';
    final icon = isManual ? Icons.link : Icons.videocam_outlined;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: theme.colorScheme.onSecondaryContainer),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSecondaryContainer,
            ),
          ),
        ],
      ),
    );
  }
}
