import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/logging/app_logger.dart';
import 'core/router/app_router.dart';
import 'core/services/foreground_service.dart';
import 'core/theme/app_theme.dart';
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
    final notifier = ref.read(audioPlayerProvider.notifier);
    if (data == 'pause') {
      try {
        if (notifier.isAllMuted) {
          notifier.unmuteAll();
          ForegroundServiceManager.updateNotification(
            title: 'Baby Monitor Active',
            text: _currentNotificationText(),
            notificationButtons: const [
              NotificationButton(id: 'pause', text: 'Pause'),
              NotificationButton(id: 'stop', text: 'Stop'),
            ],
          );
        } else {
          notifier.muteAll();
          ForegroundServiceManager.updateNotification(
            title: 'Baby Monitor — Paused',
            text: 'All cameras muted',
            notificationButtons: const [
              NotificationButton(id: 'pause', text: 'Resume'),
              NotificationButton(id: 'stop', text: 'Stop'),
            ],
          );
        }
      } catch (e) {
        appLog('FGS', 'Error handling pause: $e');
      }
    } else if (data == 'stop') {
      try {
        notifier.stopMonitoringAndCleanup();
      } catch (e) {
        appLog('FGS', 'Error handling stop: $e');
      }
    }
  }

  String _currentNotificationText() {
    final monState = ref.read(audioPlayerProvider).value;
    if (monState == null) return 'Monitoring';
    final names = monState.cameras.map((c) => c.cameraName).join(', ');
    return 'Monitoring: $names';
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
