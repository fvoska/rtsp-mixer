import 'package:flutter/material.dart';

import '../models/protect_camera.dart';

/// Small chip labelling a camera's source (UniFi, manual RTSP, or a paired
/// phone). Callers only show it when more than one source type is present —
/// a single-source list needs no distinction.
class CameraSourceBadge extends StatelessWidget {
  const CameraSourceBadge({super.key, required this.source});

  final CameraSource source;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = switch (source) {
      CameraSource.unifi => 'UniFi',
      CameraSource.manual => 'Manual',
      CameraSource.peer => 'Phone',
    };
    final icon = switch (source) {
      CameraSource.unifi => Icons.videocam_outlined,
      CameraSource.manual => Icons.link,
      CameraSource.peer => Icons.phone_android,
    };
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
