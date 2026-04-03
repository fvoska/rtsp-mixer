import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/spacing.dart';
import '../providers/audio_player_provider.dart';
import '../widgets/camera_audio_card.dart';
import '../widgets/stop_monitoring_button.dart';

class MonitoringScreen extends ConsumerStatefulWidget {
  const MonitoringScreen({super.key});

  @override
  ConsumerState<MonitoringScreen> createState() => _MonitoringScreenState();
}

class _MonitoringScreenState extends ConsumerState<MonitoringScreen> {
  @override
  void initState() {
    super.initState();
    // Start monitoring when screen loads
    Future.microtask(() {
      ref.read(audioPlayerProvider.notifier).startMonitoring();
    });
  }

  @override
  Widget build(BuildContext context) {
    final monitoringState = ref.watch(audioPlayerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Monitoring')),
      body: monitoringState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (state) {
          if (state.cameras.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          return Padding(
            padding: const EdgeInsets.all(Spacing.lg),
            child: Column(
              children: [
                for (int i = 0; i < state.cameras.length; i++) ...[
                  CameraAudioCard(
                    cameraState: state.cameras[i],
                    cameraIndex: i,
                  ),
                  if (i < state.cameras.length - 1)
                    const SizedBox(height: Spacing.lg),
                ],
              ],
            ),
          );
        },
      ),
      bottomNavigationBar: const StopMonitoringButton(),
    );
  }
}
