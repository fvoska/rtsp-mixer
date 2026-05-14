// TODO(260514-siv): delete this file once no usages remain.
// Replaced by the inline FloatingActionButton.extended on MonitoringScreen.
// Kept here in this task to keep the diff focused; follow-up cleanup will
// remove the file entirely.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/foreground_service.dart';
import '../../../core/theme/spacing.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/audio_player_provider.dart';

/// Bottom button that stops all players and navigates back to the camera list.
@Deprecated(
  'Replaced by inline FAB on MonitoringScreen — see task 260514-siv plan',
)
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
              await ref.read(storageProvider).delete('was_monitoring');
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
