// ignore_for_file: avoid_print
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../logging/app_logger.dart';

/// Top-level callback entry point for the foreground service.
/// Must be annotated to survive tree-shaking in release builds.
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(MonitoringTaskHandler());
}

/// Manages the foreground service lifecycle for overnight audio monitoring.
/// Handles init, start, stop, and notification updates.
class ForegroundServiceManager {
  static bool _initialized = false;

  /// Initialize FlutterForegroundTask options. Call once during app startup
  /// or before first use. Safe to call multiple times (idempotent).
  static void init() {
    if (_initialized) return;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'baby_monitor_service',
        channelName: 'Baby Monitor',
        channelDescription: 'Audio monitoring is active',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
    _initialized = true;
    appLog('FGS', 'Foreground service options initialized');
  }

  /// Start the foreground service with camera names in the notification.
  static Future<void> start(List<String> cameraNames) async {
    init();
    final notificationText = 'Monitoring: ${cameraNames.join(", ")}';
    await FlutterForegroundTask.startService(
      serviceId: 256,
      notificationTitle: 'Baby Monitor Active',
      notificationText: notificationText,
      notificationButtons: [
        const NotificationButton(id: 'pause', text: 'Pause'),
      ],
      callback: startCallback,
    );
    appLog('FGS', 'Foreground service started: $notificationText');
  }

  /// Update the notification text, e.g. when connection status changes.
  static Future<void> updateNotification({
    required String text,
    String title = 'Baby Monitor Active',
    List<NotificationButton>? notificationButtons,
  }) async {
    appLog('FGS', 'Notification update: $text');
    await FlutterForegroundTask.updateService(
      notificationTitle: title,
      notificationText: text,
      notificationButtons: notificationButtons,
    );
  }

  /// Stop the foreground service. Releases wake lock and WiFi lock.
  static Future<void> stop() async {
    await FlutterForegroundTask.stopService();
    appLog('FGS', 'Foreground service stopped');
  }

  /// Whether the foreground service is currently running.
  static Future<bool> get isRunning =>
      FlutterForegroundTask.isRunningService;
}

/// TaskHandler callback that runs inside the foreground **service isolate**.
/// Players live in the main isolate — this handler only receives
/// notification actions and forwards them via sendDataToMain.
///
/// NOTE: appLog() does NOT work here (different isolate). Use print()
/// for debugging — visible in `adb logcat -s flutter`.
class MonitoringTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    print('[FGS] TaskHandler.onStart (starter=$starter)');
  }

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    print('[FGS] TaskHandler.onDestroy (isTimeout=$isTimeout)');
  }

  @override
  void onNotificationButtonPressed(String id) {
    print('[FGS] Notification button pressed: $id');
    if (id == 'pause') {
      FlutterForegroundTask.sendDataToMain('pause');
    }
  }

  @override
  void onNotificationPressed() {
    print('[FGS] Notification body pressed');
  }
}
