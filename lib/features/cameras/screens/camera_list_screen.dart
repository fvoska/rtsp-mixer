import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/spacing.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/camera_provider.dart';

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
            onPressed: () => ref.read(authNotifierProvider.notifier).logout(),
          ),
        ],
      ),
      body: cameraState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e', style: TextStyle(color: theme.colorScheme.error))),
        data: (state) {
          if (state.cameras.isEmpty) {
            return const Center(child: Text('No cameras found.'));
          }
          final atLimit = state.selectedIds.length >= 2;
          return Column(children: [
            Padding(
              padding: const EdgeInsets.all(Spacing.md),
              child: Text('Choose 1 or 2 cameras to monitor', style: theme.textTheme.bodyLarge),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: state.cameras.length,
                itemBuilder: (_, i) {
                  final cam = state.cameras[i];
                  final selected = state.selectedIds.contains(cam.id);
                  final muted = atLimit && !selected;
                  return Opacity(
                    opacity: muted ? 0.5 : 1.0,
                    child: CheckboxListTile(
                      value: selected,
                      onChanged: (_) => ref.read(cameraNotifierProvider.notifier).toggleCamera(cam.id),
                      title: Text(cam.name ?? 'Unnamed Camera'),
                      subtitle: Text(cam.state),
                      secondary: Container(
                        width: 8, height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: cam.isConnected ? AppTheme.statusOnline : AppTheme.statusOffline,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ]);
        },
      ),
      bottomNavigationBar: cameraState.whenOrNull(
        data: (state) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.lg, vertical: Spacing.md),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: state.canStartMonitoring ? () => context.go('/monitoring') : null,
                child: const Text('Start Monitoring'),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
