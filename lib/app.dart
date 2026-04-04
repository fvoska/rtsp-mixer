import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/logging/app_logger.dart';
import 'core/router/app_router.dart';
import 'core/services/foreground_service.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/providers/auth_provider.dart';
import 'features/monitoring/providers/audio_player_provider.dart';

class App extends ConsumerStatefulWidget {
  const App({super.key});

  @override
  ConsumerState<App> createState() => _AppState();
}

class _AppState extends ConsumerState<App> {
  @override
  void initState() {
    super.initState();
    FlutterForegroundTask.addTaskDataCallback(_onTaskData);
  }

  @override
  void dispose() {
    FlutterForegroundTask.removeTaskDataCallback(_onTaskData);
    super.dispose();
  }

  void _onTaskData(Object data) {
    appLog('FGS', 'Received task data: $data (${data.runtimeType})');
    final action = data is String ? data : (data is Map ? data['action'] : null);
    if (action == 'toggle') {
      appLog('FGS', 'Toggle action — muting/unmuting all cameras');
      try {
        final notifier = ref.read(audioPlayerProvider.notifier);
        final monState = ref.read(audioPlayerProvider).value;
        if (monState != null && monState.cameras.isNotEmpty) {
          final anyUnmuted = monState.cameras.any((c) => !c.isMuted);
          for (int i = 0; i < monState.cameras.length; i++) {
            if (anyUnmuted && !monState.cameras[i].isMuted) {
              notifier.toggleMute(i);
            } else if (!anyUnmuted && monState.cameras[i].isMuted) {
              notifier.toggleMute(i);
            }
          }
        }
      } catch (e) {
        appLog('FGS', 'Error handling toggle: $e');
      }
    } else if (action == 'stop') {
      appLog('FGS', 'Stop action from foreground service');
      ref.read(audioPlayerProvider.notifier).stopMonitoring();
      ForegroundServiceManager.stop();
      ref.read(storageProvider).delete('was_monitoring');
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    return WithForegroundTask(
      child: MaterialApp.router(
        title: 'RTSP Mixer',
        theme: AppTheme.dark,
        routerConfig: router,
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}
