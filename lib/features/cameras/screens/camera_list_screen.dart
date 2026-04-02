import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/spacing.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/camera_provider.dart';

/// Camera selection screen (D-04, D-05, D-06).
///
/// Shows discovered cameras with name, type, and online/offline indicator.
/// Allows selecting 1-2 cameras for monitoring. Enforces selection limit
/// with visual muting of unchecked rows when 2 are selected.
class CameraListScreen extends ConsumerWidget {
  const CameraListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cameraState = ref.watch(cameraNotifierProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Cameras'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: () {
              ref.read(authNotifierProvider.notifier).logout();
            },
          ),
        ],
      ),
      body: cameraState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(Spacing.lg),
            child: Text(
              error.toString(),
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.error,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        data: (state) {
          if (state.cameras.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(Spacing.lg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'No Cameras Found',
                      style: theme.textTheme.headlineMedium,
                    ),
                    const SizedBox(height: Spacing.md),
                    Text(
                      'No cameras were discovered on this Protect console. '
                      'Check that your cameras are adopted and RTSP is enabled '
                      'in each camera\'s advanced settings.',
                      style: theme.textTheme.bodyLarge,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }

          final atLimit = state.selectedIds.length >= 2;

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Spacing.lg,
                  vertical: Spacing.md,
                ),
                child: Text(
                  'Choose 1 or 2 cameras to monitor',
                  style: theme.textTheme.bodyLarge,
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: state.cameras.length,
                  itemBuilder: (context, index) {
                    final camera = state.cameras[index];
                    final isSelected =
                        state.selectedIds.contains(camera.id);
                    final isMuted = atLimit && !isSelected;

                    return Opacity(
                      opacity: isMuted ? 0.5 : 1.0,
                      child: CheckboxListTile(
                        value: isSelected,
                        onChanged: (_) {
                          ref
                              .read(cameraNotifierProvider.notifier)
                              .toggleCamera(camera.id);
                        },
                        title: Text(camera.name ?? 'Unnamed Camera'),
                        subtitle: Text(camera.type),
                        secondary: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: camera.isConnected
                                ? AppTheme.statusOnline
                                : AppTheme.statusOffline,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: cameraState.when(
        loading: () => const SizedBox.shrink(),
        error: (_, __) => const SizedBox.shrink(),
        data: (state) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Spacing.lg,
              vertical: Spacing.md,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    onPressed: state.canStartMonitoring
                        ? () => GoRouter.of(context).go('/monitoring')
                        : null,
                    child: const Text('Start Monitoring'),
                  ),
                ),
                if (!state.canStartMonitoring)
                  Padding(
                    padding: const EdgeInsets.only(top: Spacing.sm),
                    child: Opacity(
                      opacity: 0.6,
                      child: Text(
                        'Select 1 or 2 cameras',
                        style: theme.textTheme.bodyLarge,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
