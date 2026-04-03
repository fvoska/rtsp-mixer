import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/foreground_service.dart';
import '../../../core/theme/spacing.dart';
import '../providers/audio_player_provider.dart';

/// Bottom button that stops all players and navigates back to the camera list.
class StopMonitoringButton extends ConsumerWidget {
  const StopMonitoringButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.lg,
          vertical: Spacing.md,
        ),
        child: SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlinedButton(
            onPressed: () async {
              await ref.read(audioPlayerProvider.notifier).stopMonitoring();
              await ForegroundServiceManager.stop();
              if (context.mounted) context.go('/cameras');
            },
            child: const Text('Stop Monitoring'),
          ),
        ),
      ),
    );
  }
}
